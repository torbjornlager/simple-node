:- module(node,
       [ node/1                  % +Port
       ]).

/** <module> Node -- simple HTTP endpoint for toplevel queries

This module exposes a small HTTP interface for evaluating Prolog goals
through a toplevel actor. Requests are served by `/call`, with the goal
and query options passed as HTTP parameters.

For paged queries, a suspended toplevel actor may be cached between
requests. This allows later calls with the next offset to continue from
the already running enumeration rather than restarting the goal.

Currently, only the `prolog` response format is implemented. Requests
for `json` receive a simple "not yet implemented" response.
*/


                /*******************************
                *             NODE             *
                *******************************/


:- use_module(actors, [
       receive/2,
       exit/2
   ]).
:- use_module(toplevel_actors, [
       toplevel_spawn/2,
       toplevel_call/3,
       toplevel_next/2
   ]).

:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_parameters)).
:- use_module(library(http/thread_httpd)).
:- use_module(library(settings)).


:- setting(cache_size, integer, 100, 'Max number of cache entries').
:- setting(timeout, number, 100, 'Timeout in seconds').


:- http_handler(root(call), node_controller_http, []).


%!  node(+Port) is det.
%
%   Start the node HTTP server on Port.

node(Port) :-
    http_server(http_dispatch, [port(Port)]).


%!  compute_answer(+Goal, +Template, +Offset, +Limit, -Answer) is det.
%
%   Compute one answer term for Goal using the given Template, Offset,
%   and Limit. If a suspended toplevel matching the same goal/template
%   pair is cached at the given offset, continue from that process.
%   Otherwise start a fresh toplevel for the query.
%
%   For a naive implementation that doesn't implement caching,
%   replace with this:
%
%   compute_answer(Goal, Template, Offset, Limit, Answer) :-
%       once(answer(Goal, Template, Offset, Limit, Answer)).


compute_answer(Goal, Template, Offset, Limit, Answer) :-
    goal_id(Goal-Template, Gid),
    (   cache_retract(Gid, Offset, Pid)
    ->  thread_self(Self),
        toplevel_next(Pid, [
            limit(Limit),
            target(Self)
        ])
    ;   toplevel_spawn(Pid, [
            link(false),
            session(false)
        ]),
        toplevel_call(Pid, Goal, [
            template(Template),
            offset(Offset),
            limit(Limit)
        ])
    ),
    setting(timeout, Timeout),
    receive({
        success(Pid, Slice, true) ->
            NextOffset is Offset + Limit,
            cache_update(Gid, NextOffset, Pid),
            Answer = success(Slice, true) ;
        success(Pid, Slice, false) ->
            Answer = success(Slice, false) ;
        failure(Pid) ->
            Answer = failure ;
        error(Pid, Error) ->
            Answer = error(Error)
    }, [
        timeout(Timeout),
        on_timeout((
            Answer = error(timeout),
            exit(Pid, kill)
        ))
    ]).


                /*******************************
                *             HTTP            *
                *******************************/


node_controller_http(Request) :-
    http_parameters(Request, [
        goal(GoalAtom, [atom]),
        template(TemplateAtom, [default(GoalAtom)]),
        offset(Offset, [integer, default(0)]),
        limit(Limit, [integer, default(10000000000)]),
        format(Format, [atom, default(json)])
    ]),
    atomic_list_concat([GoalAtom, +, TemplateAtom], QTAtom),
    read_term_from_atom(QTAtom, Goal+Template, []),
    compute_answer(Goal, Template, Offset, Limit, Answer),
    respond_with_answer(Format, Answer).


respond_with_answer(prolog, Answer) :- !,
    format('Content-type: text/plain; charset=UTF-8~n~n'),
    write_term(Answer, [
        quoted(true),
        ignore_ops(true),
        fullstop(true),
        nl(true),
        blobs(portray)
    ]).
respond_with_answer(json, _Answer) :-
    format('Content-type: text/plain; charset=UTF-8~n~n'),
    writeln('JSON output is not yet implemented'),
    writeln('Use format=prolog').



                /*******************************
                *            CACHE            *
                *******************************/


:- dynamic cache/3.


goal_id(GoalTemplate, Gid) :-
    copy_term(GoalTemplate, Gid0),
    numbervars(Gid0, 0, _),
    term_hash(Gid0, Gid).


cache_retract(Gid, Offset, Pid) :-
    once(retract(cache(Gid, Offset, Pid))).


cache_update(Gid, Offset, Pid) :-
    assertz(cache(Gid, Offset, Pid)),
    trim_cache.


trim_cache :-
    setting(cache_size, Size),
    predicate_property(cache(_, _, _), number_of_clauses(Count)),
    (   Count > Size
    ->  once(retract(cache(_, _, _))),
        trim_cache
    ;   true
    ).
