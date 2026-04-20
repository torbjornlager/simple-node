:- module(toplevel_actors,  
       [ spawn/1,                % :Goal
         spawn/2,                % :Goal, -Pid
         spawn/3,                % :Goal, -Pid, +Options
         self/1,                 % -Pid
         monitor/2,              % +PidOrName, -Ref
         demonitor/1,            % +Ref
         demonitor/2,            % +Ref, +Options
         register/2,             % +Name, +Pid
         unregister/1,           % +Name
         whereis/2,              % +Name, -Pid
         exit/1,                 % +Reason
         exit/2,                 % +Pid, +Reason
         (!)/2,                  % +Pid, +Message
         send/2,                 % +Pid, +Message
         input/2,                % +Prompt, ?Answer
         input/3,                % +Prompt, ?Answer, +Options
         respond/2,              % +Pid, +Answer
         output/1,               % +Term
         output/2,               % +Term, +Options
         receive/1,              % +ReceiveClauses
         receive/2,              % +ReceiveClauses, +Options
         make_ref/1,             % -Ref
         flush/0,

         toplevel_spawn/1,       % -Pid
         toplevel_spawn/2,       % -Pid, +Options
         toplevel_call/2,        % +Pid, :Goal
         toplevel_call/3,        % +Pid, :Goal, +Options
         toplevel_next/1,        % +Pid
         toplevel_next/2,        % +Pid, +Options
         toplevel_stop/1,        % +Pid                   
         toplevel_abort/1,       % +Pid    

         op(800,  xfx, !),       %
         op(200,  xfx, @),       %
         op(1000, xfy, if)       %
       ]).

/** <module> Toplevel actors -- shell-style control of goal execution

This library builds a small Prolog toplevel protocol on top of the
actor primitives from actors.pl. A toplevel actor is an ordinary actor
running a simple state machine that accepts commands from another
process and sends back answer terms such as:

  - `success(Pid, Slice, More)`
  - `failure(Pid)`
  - `error(Pid, Error)`

Because a toplevel actor is still just an actor, goals running inside it
may also communicate with the parent process by using the ordinary
`output/1-2` and `input/2-3` predicates exported by the underlying
actors library.

What this module adds on top of actors.pl:

  - toplevel_spawn/1-2 to create a toplevel actor
  - toplevel_call/2-3 to run a goal inside it
  - toplevel_next/1-2 to ask for the next slice of solutions
  - toplevel_stop/1 to stop an unfinished enumeration
  - toplevel_abort/1 to abort a running goal

## PTCP states {#toplevel-ptcp-states}

Internally, the actor behaves as a small Prolog Toplevel Control Process
(PTCP) with three states:

  - *s1* waits for a `'$call'(Goal, Options)` message
  - *s2* computes one answer term for the goal
  - *s3* waits for either `'$next'(Options)` or `'$stop'` after a
    partial success

If a reply is `success(Pid, Slice, true)`, the query has more solutions
and the PTCP is suspended in state *s3*. The client may then send
`toplevel_next/1-2` to continue or `toplevel_stop/1` to discard the
remaining solutions and return the PTCP to state *s1*.

## Example {#toplevel-actors-example}

==
?- toplevel_spawn(Pid, [session(true)]).
Pid = <thread>(...).

?- toplevel_call(Pid, between(1,5,N), [
       template(N),
       limit(2)
   ]).
true.

?- receive({Answer -> true}).
Answer = success(Pid, [1,2], true).

?- toplevel_next(Pid).
true.

?- receive({Answer -> true}).
Answer = success(Pid, [3,4], true).
==

@author Torbjorn Lager
*/


                /*******************************
                *           TOPLEVEL          *
                *******************************/


:- use_module(actors).
:- use_module(library(option)).


:- meta_predicate(toplevel_call(+, 0)).
:- meta_predicate(toplevel_call(+, 0, +)).
    
    
%!  toplevel_spawn(-Pid) is det.
%!  toplevel_spawn(-Pid, +Options) is det.
%
%   Spawn a new toplevel actor. The new actor's PID is unified with
%   Pid. Options:
%
%     - session(+Bool)
%       If `true`, the toplevel remains alive after one goal has run to
%       completion and returns to its ready state, accepting more calls.
%       If `false`, the toplevel exits after the first completed call.
%       Default: `false`.
%     - target(+PidOrName)
%       Actor that should receive answer, output, and prompt messages
%       from the toplevel. Default: the process that called
%       toplevel_spawn/1-2.
%
%   In addition, ordinary spawn/3 options such as `monitor(true)` and
%   `link(true)` are accepted and handled by the underlying actor
%   runtime.

toplevel_spawn(Pid) :-
    toplevel_spawn(Pid, []).

toplevel_spawn(Pid, Options) :-
    self(Self),
    option(target(Target), Options, Self),
    option(session(Continue), Options, false),
    spawn(session(Pid, Target, Continue), Pid, Options).


                /*******************************
                *        ANSWER SLICING       *
                *******************************/

% Compute one slice of solutions for Goal in the style of findall/3,
% but starting at Offset and collecting at most Limit answers.
% 
% Note that findnsols/4 is a built-in predicate in SWI-Prolog. It is
% very important in this implementation.

slice(Goal, Template, Offset, Limit, Slice) :-
    findnsols(Limit, Template, offset(Offset, Goal), Slice).


% Turn one sliced execution step into a protocol-level answer term.

answer(Goal, Template, Offset, Limit, Answer) :-
    catch(
        call_cleanup(slice(Goal, Template, Offset, Limit, Slice),
                     Det = true),
        Error, true),
    (   Slice == []
    ->  Answer = failure
    ;   nonvar(Error)
    ->  Answer = error(Error)
    ;   var(Det)
    ->  Answer = success(Slice, true)
    ;   Det = true
    ->  Answer = success(Slice, false)
    ).
   

                /*******************************
                *      PTCP STATE MACHINE     *
                *******************************/

% Run the PTCP. Aborting a goal throws '$abort_goal', after which the
% toplevel is restarted in its ready state.

session(Pid, Target, Continue) :-
    catch(state_1(Pid, Target, Continue), 
          '$abort_goal',
          session(Pid, Target, Continue)).
   

% State s1: wait for a call request, compute one answer term, send it to
% the current target, and move either back to s1 or into s3.

state_1(Pid, Target0, Continue) :-
    receive({
        '$call'(Goal, Options) ->
            option(template(Template), Options, Goal),
            option(offset(Offset), Options, 0),
            option(limit(Limit0), Options, 10 000 000 000),
            option(target(Target1), Options, Target0),
            Limit = count(Limit0),
            state_2(Goal, Template, Offset, Limit, Pid, Answer),
            Target = target(Target1),
            arg(1, Target, Out),
            Out ! Answer,
            (   arg(3, Answer, true)
            ->  state_3(Limit, Target)  
            ;   true
            ) 
        }),
    (   Continue == false
    ->  true
    ;   state_1(Pid, Target0, Continue)
    ).


% State s2: compute one answer slice and attach the toplevel's PID.

state_2(Goal, Template, Offset, Limit, Pid, Answer) :-
    answer(Goal, Template, Offset, Limit, Answer0),
    add_pid(Answer0, Pid, Answer).


add_pid(success(Slice, More), Pid, success(Pid, Slice, More)).
add_pid(failure, Pid, failure(Pid)).
add_pid(error(Term), Pid, error(Pid, Term)).


% State s3: after a partial success, wait for either another batch
% request or a stop command.

state_3(Limit, Target) :-
    receive({
        '$next'(Options2) ->
            (   option(limit(NewLimit), Options2)
            ->  nb_setarg(1, Limit, NewLimit)
            ;   true
            ),
            (   option(target(NewTarget), Options2)
            ->  nb_setarg(1, Target, NewTarget)
            ;   true
            ),
            fail ;
        '$stop' -> true
    }),
    !.


%!  toplevel_call(+Pid, :Goal) is det.
%!  toplevel_call(+Pid, :Goal, +Options) is det.
%
%   Ask the toplevel actor identified by Pid to evaluate Goal. The
%   result is sent asynchronously as one answer term to the target
%   process. Options:
%
%     - template(+Template)
%       Collect solutions in the form of Template. Default: Goal.
%     - offset(+NonNeg)
%       Skip this many solutions before starting to collect answers.
%       Default: `0`.
%     - limit(+Positive)
%       Maximum number of solutions to return in this answer term.
%       Default: a very large number.
%     - target(+PidOrName)
%       Override the toplevel's current target for this call.
%
%   If the reply is `success(Pid, Slice, true)`, solutions may remain 
%   and the toplevel waits for toplevel_next/1-2 or toplevel_stop/1.

toplevel_call(Pid, Goal) :-
    toplevel_call(Pid, Goal, []).

toplevel_call(Pid, Goal0, Options) :-
    strip_module(Goal0, _, Goal),
    Pid ! '$call'(Goal, Options).


%!  toplevel_next(+Pid) is det.
%!  toplevel_next(+Pid, +Options) is det.
%
%   Continue a suspended enumeration after a previous answer term of the
%   form `success(Pid, Slice, true)`. Options:
%
%     - limit(+Positive)
%       Change the maximum number of solutions returned in each
%       subsequent slice.
%     - target(+PidOrName)
%       Redirect subsequent answer, output, and prompt messages for the
%       suspended computation.

toplevel_next(Pid) :-
    toplevel_next(Pid, []).

toplevel_next(Pid, Options) :-
    Pid ! '$next'(Options). 


%!  toplevel_stop(+Pid) is det.
%
%   Stop a suspended enumeration and return the toplevel to its ready
%   state. This only has an effect while the PTCP is waiting in state
%   *s3* after a partial success.

toplevel_stop(Pid) :-
    Pid ! '$stop'.


%!  toplevel_abort(+Pid) is det.
%
%   Abort the goal currently running inside the toplevel identified by
%   Pid. If the process exists, it is signaled with `'$abort_goal'`,
%   which causes the PTCP to restart in its ready state. If Pid does not
%   exist, the predicate succeeds silently.

toplevel_abort(Pid) :-
    catch(thread_signal(Pid, throw('$abort_goal')), 
          error(existence_error(_,_), _), 
          true).  
