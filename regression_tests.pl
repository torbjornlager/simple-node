:- use_module(term_wire).
:- use_module(node, []).
:- use_module(rpc).
:- use_module(actors).
:- use_module(library(plunit)).
:- use_module(library(time)).
:- use_module(library(thread)).
:- use_module(library(settings)).
:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_open)).
:- use_module(library(uri)).
:- use_module(library(clpfd), []).

:- begin_tests(contracts, [cleanup(node:clear_cache)]).

test(key_literal_var_is_data) :-
    goal_key(p(X)-v(X), A), goal_key(p('$VAR'(0))-v('$VAR'(0)), B),
    assertion(A \== B),
    goal_key(p(Y)-v(Y), A), goal_key(p(_)-v(_), C), assertion(A \== C).

test(text_and_sharing) :-
    parse_goal_template('X="ab"', 'v(X,X)', Goal, Template),
    call(Goal), assertion(Template == v([a,b],[a,b])).

test(cycle, [throws(error(representation_error(cyclic_term),_))]) :-
    X=f(X), portable_term(X).
test(attributes, [throws(error(representation_error(constraints),_))]) :-
    clpfd:in(X, '..'(1,3)), portable_term(X).

test(guard_control_keeps_message) :-
    self(Me), Me ! first, Me ! second,
    catch(receive({first if throw('$abort_goal') -> fail}), '$abort_goal', true),
    receive({A -> true}), receive({B -> true}),
    assertion(A-B == first-second).

timeout_result(done).

test(timeout_runs_in_caller_module) :-
    receive({never->fail}, [timeout(0),on_timeout(timeout_result(Result))]),
    assertion(Result==done).

test(catchall_stays_variable) :-
    self(Me), Me ! box(X), receive({M -> true}),
    assertion(M = box(_)), assertion(var(X)).

test(timeout_does_not_restart) :-
    self(Me),
    thread_create(forall(between(1,100,_),
                        (thread_send_message(Me, unmatched),sleep(0.002))), Sender, []),
    get_time(T0), receive({never -> fail}, [timeout(0.03)]), get_time(T1),
    assertion(T1-T0 < 0.15),
    thread_join(Sender, _),
    drain_unmatched.

test(partial_exception_and_next, [cleanup(node:clear_cache)]) :-
    Goal=(X=a;X=b;throw(after_two)),
    node:compute_answer(Goal,X,0,5,A), assertion(A == success([a,b],true)),
    node:compute_answer(Goal,X,2,5,B), assertion(B == error(after_two)).

test(exception_after_an_earlier_page, [cleanup(node:clear_cache)]) :-
    Goal=(X=a;X=b;X=c;throw(after_three)),
    node:compute_answer(Goal,X,0,2,A),
    node:compute_answer(Goal,X,2,2,B),
    node:compute_answer(Goal,X,3,2,C),
    assertion([A,B,C] == [success([a,b],true),success([c],true),error(after_three)]).

test(no_lookahead_or_replay, [cleanup(node:clear_cache)]) :-
    thread_self(Me),
    Goal=((X=a;X=b),thread_send_message(Me,seen(X))),
    node:compute_answer(Goal,X,0,1,A),
    receive({seen(First)->true}),
    receive({seen(_)->fail},[timeout(0)]),
    node:compute_answer(Goal,X,1,1,B),
    receive({seen(Second)->true}),
    assertion(A==success([a],true)), assertion(B==success([b],false)),
    assertion(First-Second==a-b).

test(literal_key_does_not_resume_variable_query, [cleanup(node:clear_cache)]) :-
    node:compute_answer(member(X,[a,b]),X,0,1,_),
    node:compute_answer(member('$VAR'(0),[a,b]),'$VAR'(0),1,1,A),
    assertion(A==failure).

test(next_redirects_to_a_distinct_live_queue) :-
    setup_call_cleanup(message_queue_create(Q1),
      setup_call_cleanup(message_queue_create(Q2),
        setup_call_cleanup(
          toplevel_actors:toplevel_spawn(Pid,[link(false),target(Q1)]),
          (toplevel_actors:toplevel_call(Pid,user:between(1,3,X),[template(X),limit(1)]),
           thread_get_message(Q1,success(Pid,[1],true),[timeout(1)]),
           toplevel_actors:toplevel_next(Pid,[target(Q2)]),
           thread_get_message(Q2,success(Pid,[2],true),[timeout(1)])),
          actors:exit(Pid,stopped)),
        message_queue_destroy(Q2)),
      message_queue_destroy(Q1)).

test(concurrent_paging, [cleanup(node:clear_cache)]) :-
    concurrent_maplist(query_sequence, [1,2,3,4,5,6,7,8], Results),
    maplist(=([success([1,2],true),success([3,4],true),success([5],false)]), Results).

test(native_string_is_rejected, [throws(error(representation_error(transportable_term),_))]) :-
    string_chars(S,[a,b]), portable_term(S).

test(attributed_solution_is_rejected) :-
    node:compute_answer(clpfd:in(X,'..'(1,3)),X,0,1,A),
    assertion(A = error(error(representation_error(constraints),_))).

test(page_timeout_reclaims_worker,
     [setup(set_setting(node:timeout,0.03)),cleanup(set_setting(node:timeout,30))]) :-
    thread_self(Me),
    node:compute_answer((thread_self(P),thread_send_message(Me,producer(P)),sleep(10)),true,0,1,A),
    assertion(A = error(error(resource_error(time),_))),
    receive({producer(Pid)->true}), wait_stopped(Pid).

test(cyclic_exception_is_portable) :-
    node:compute_answer((X=f(X),throw(X)),true,0,1,A),
    assertion(A = error(error(representation_error(cyclic_term),_))).

test(cyclic_solution_is_rejected) :-
    node:compute_answer(X=f(X),X,0,1,A),
    assertion(A = error(error(representation_error(cyclic_term),_))).

test(eviction_stops_worker,
     [setup(set_setting(node:cache_size,0)),cleanup(set_setting(node:cache_size,100))]) :-
    self(Me),
    node:compute_answer((thread_self(P),thread_send_message(Me,producer(P)),between(1,3,X)),X,0,1,_),
    receive({producer(Pid) -> true}), wait_stopped(Pid).

test(interrupted_request_stops_worker) :-
    self(Me),
    catch(call_with_time_limit(0.1,
        node:compute_answer((thread_self(P),thread_send_message(Me,producer(P)),sleep(10)),true,0,1,_)),
        time_limit_exceeded, true),
    receive({producer(Pid) -> true}), wait_stopped(Pid),
    assertion(\+ node:cache(_,_,Pid)).

test(changed_page_size, [cleanup(node:clear_cache)]) :-
    node:compute_answer(between(1,6,X), X, 0, 2, A),
    node:compute_answer(between(1,6,X), X, 2, 3, B),
    node:compute_answer(between(1,6,X), X, 5, 2, C),
    assertion([A,B,C] == [success([1,2],true),success([3,4,5],true),success([6],false)]).

test(http_rpc_text_literal_sharing_and_error) :-
    setup_call_cleanup(
        node:node(Port),
        (format(atom(URI),'http://localhost:~d',[Port]),
         findall(X,rpc(URI,member(X,['New York','$VAR'(0),[a,b]]),[limit(1)]),Xs),
         assertion(Xs == ['New York','$VAR'(0),[a,b]]),
         once(rpc(URI, X=pair(Y,Y))), assertion(X == pair(Y,Y)), assertion(var(Y)),
         catch(findall(V,rpc(URI,(V=a;V=b;throw(boom)),[limit(5)]),_),boom,Caught=true),
         assertion(Caught==true),
         http_answer(URI,'X="ab"','X',A), assertion(A==success([[a,b]],false))),
        node:stop_node(Port)).

test(invalid_limit, [throws(error(type_error(positive_integer,0),_))]) :-
    node:compute_answer(true,true,0,0,_).

:- end_tests(contracts).

http_answer(URI, Goal, Template, Answer) :-
    uri_query_components(Query,[goal=Goal,template=Template]),
    atomic_list_concat([URI,'/call?',Query],URL),
    setup_call_cleanup(http_open(URL,S,[]),read_term(S,Answer,[]),close(S)).

drain_unmatched :- receive({unmatched -> drain_unmatched}, [timeout(0)]).
wait_stopped(Pid) :-
    call_with_time_limit(1, wait_stopped_(Pid)).
wait_stopped_(Pid) :-
    (catch(thread_property(Pid,status(running)),_,fail)
    -> sleep(0.01), wait_stopped_(Pid); true).

query_sequence(_, [A,B,C]) :-
    node:compute_answer(between(1,5,X),X,0,2,A),
    node:compute_answer(between(1,5,X),X,2,2,B),
    node:compute_answer(between(1,5,X),X,4,2,C).
