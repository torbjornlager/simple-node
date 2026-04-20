:- module(rpc,
       [ rpc/2,                  % +URI, :Goal
         rpc/3                   % +URI, :Goal, +Options
       ]).

/** <module> RPC -- simple HTTP-based remote Prolog calls

This module provides a small client-side wrapper around the node `/call`
endpoint. A goal is serialized into HTTP query parameters, sent to a
remote node, and its solutions are yielded back to the caller one by
one.

The remote node answers in the `prolog` format. If the answer reports
that more solutions exist, rpc/2-3 automatically issues follow-up
requests with the next offset until all solutions have been consumed or
the caller stops backtracking.

## Examples {#rpc-examples}

==
?- rpc('http://localhost:3060', member(X, [a,b,c])).
X = a ;
X = b ;
X = c.
       
% The following example shows if caching works or not:

?- rpc('http://localhost:3060', (sleep(2), X=a ; X=b), [limit(1)]).
X = a ;
X = b.
==
*/


                 /*******************************
                 *             RPC             *
                 *******************************/


:- use_module(library(http/http_open)).
:- use_module(library(url)).
:- use_module(library(option)).


:- meta_predicate(rpc(+, 0)).
:- meta_predicate(rpc(+, 0, +)).


%!  rpc(+URI, :Goal) is nondet.
%!  rpc(+URI, :Goal, +Options) is nondet.
%
%   Call Goal against the node identified by URI. Solutions are returned
%   to the caller one at a time on backtracking. Options:
%
%     - limit(+Positive)
%       Maximum number of solutions to fetch in each HTTP request.
%       Default: a very large number.
%
%   Any additional options are passed to http_open/3.

rpc(URI, Goal) :-
    rpc(URI, Goal, []).

rpc(URI, Goal, Options) :-
    parse_url(URI, Parts),
    term_variables(Goal, Vars),
    Template =.. [v|Vars],
    format(atom(GoalAtom), "(~p)", [Goal]),
    format(atom(TemplateAtom), "(~p)", [Template]),
    option(limit(Limit), Options, 10000000000),
    rpc_page(Template, 0, Limit, GoalAtom, TemplateAtom, Parts, Options).


rpc_page(Template, Offset, Limit, GoalAtom, TemplateAtom, Parts, Options) :-
    parse_url(ExpandedURI, [
        path('/call'),
        search([goal=GoalAtom, template=TemplateAtom,
                offset=Offset, limit=Limit, format=prolog])
      | Parts
    ]),
    setup_call_cleanup(
        http_open(ExpandedURI, Stream, Options),
        read(Stream, Answer),
        close(Stream)
    ),
    rpc_answer(Answer, Template, Offset, Limit, GoalAtom, TemplateAtom, Parts, Options).


rpc_answer(success(Slice, true), Template, Offset, Limit, GoalAtom, TemplateAtom, Parts, Options) :- !,
    (   member(Template, Slice)
    ;   NewOffset is Offset + Limit,
        rpc_page(Template, NewOffset, Limit, GoalAtom, TemplateAtom, Parts, Options)
    ).
rpc_answer(success(Slice, false), Template, _, _, _, _, _, _) :-
    member(Template, Slice).
rpc_answer(failure, _, _, _, _, _, _, _) :-
    fail.
rpc_answer(error(Error), _, _, _, _, _, _, _) :-
    throw(Error).
