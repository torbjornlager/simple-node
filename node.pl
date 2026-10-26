:- module(node, [node/1, stop_node/1, clear_cache/0]).

/** <module> A local teaching node with request-owned query continuations.
    This runs trusted code with host authority; it is not a public service.
*/
:- use_module(actors, []).
:- use_module(toplevel_actors, [toplevel_spawn/2, toplevel_call/3, toplevel_next/2]).
:- use_module(term_wire).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_parameters)).
:- use_module(library(http/thread_httpd)).
:- use_module(library(settings)).
:- use_module(library(aggregate)).

:- setting(cache_size, integer, 100, 'Maximum suspended continuations').
:- setting(timeout, number, 30, 'Seconds waiting for a page').
:- dynamic cache/3.
:- http_handler(root(call), node_controller_http, []).

node(Port) :- http_server(http_dispatch, [port(localhost:Port)]).
stop_node(Port) :- http_stop_server(Port, []), clear_cache.

node_controller_http(Request) :-
    http_parameters(Request, [goal(GA,[atom]), template(TA,[atom,default(GA)]),
        offset(Offset,[integer,default(0)]), limit(Limit,[integer,optional(true)]),
        format(Format,[atom,default(prolog)])]),
    catch((must_be(nonneg, Offset),
           (var(Limit) -> true; must_be(positive_integer, Limit)),
           parse_goal_template(GA, TA, Goal, Template),
           compute_answer(Goal, Template, Offset, Limit, Answer)),
          E, safe_answer(error(E), Answer)),
    respond_with_answer(Format, Answer).

compute_answer(Goal, Template, Offset, Limit, Answer) :-
    must_be(nonneg, Offset),
    (var(Limit) -> true; must_be(positive_integer, Limit)),
    goal_key(Goal-Template, Key),
    Owner = owner(none, request),
    setup_call_cleanup(message_queue_create(Queue),
        setup_call_cleanup(true,
            query_page(Queue, Owner, Key, Goal, Template, Offset, Limit, Answer),
            release_owner(Owner)),
        message_queue_destroy(Queue)).

query_page(Queue, Owner, Key, Goal, Template, Offset, Limit, Answer) :-
    (var(Limit) -> Limits=[]; Limits=[limit(Limit)]),
    sig_atomic((
        (nonvar(Limit), cache_retract(Key, Offset, Pid) -> Mode=next
        ; toplevel_spawn(Pid, [link(false),session(false),target(Queue)]), Mode=call),
        nb_setarg(1, Owner, Pid))),
    (Mode == next -> toplevel_next(Pid, [target(Queue)|Limits])
    ; toplevel_call(Pid, user:Goal,
                   [template(Template),offset(Offset),target(Queue)|Limits])),
    setting(timeout, Timeout),
    (thread_get_message(Queue, Message, [timeout(Timeout)])
    -> page_message(Message, Pid, Candidate)
    ; Candidate=error(error(resource_error(time),_))),
    safe_answer(Candidate, Answer),
    (Answer = success(Slice,true), nonvar(Limit)
    -> length(Slice, Count), Next is Offset+Count,
       sig_atomic((cache_update(Key, Next, Pid), nb_setarg(2, Owner, cache)))
    ; true).

page_message(success(Pid,Slice,More), Expected, success(Slice,More)) :-
    Pid == Expected, (More == true; More == false), !.
page_message(failure(Pid), Expected, failure) :- Pid == Expected, !.
page_message(error(Pid,E), Expected, error(E)) :- Pid == Expected, !.
page_message(Message, _, error(unexpected_message(Message))).

release_owner(owner(none,_)) :- !.
release_owner(owner(_,cache)) :- !.
release_owner(owner(Pid,request)) :- stop_toplevel(Pid).

stop_toplevel(Pid) :-
    actors:exit(Pid, stopped).

cache_retract(Key, Offset, Pid) :-
    with_mutex(continuation_cache, once(retract(cache(Key,Offset,Pid)))).

cache_update(Key, Offset, Pid) :-
    with_mutex(continuation_cache,
        (assertz(cache(Key,Offset,Pid)), evict_excess(Evicted))),
    maplist(stop_toplevel, Evicted).

evict_excess(Evicted) :-
    setting(cache_size, Max), must_be(nonneg, Max),
    aggregate_all(count, cache(_,_,_), Count),
    (Count > Max -> once(retract(cache(_,_,Pid))),
                   Evicted=[Pid|Rest], evict_excess(Rest)
    ; Evicted=[]).

clear_cache :-
    sig_atomic((with_mutex(continuation_cache,
        findall(Pid, retract(cache(_,_,Pid)), Pids)),
        maplist(stop_toplevel, Pids))).

respond_with_answer(prolog, Candidate) :- !,
    safe_answer(Candidate, Answer),
    format('Content-type: application/x-prolog; charset=UTF-8~n~n'),
    write_term(Answer, [quoted(true),ignore_ops(true),numbervars(false),
                        fullstop(true),nl(true)]).
respond_with_answer(json, _) :- !,
    format('Content-type: text/plain; charset=UTF-8~n~n'),
    writeln('JSON output is not yet implemented'), writeln('Use format=prolog').
respond_with_answer(Format, _) :- domain_error(answer_format, Format).
