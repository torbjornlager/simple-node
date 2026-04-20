:- use_module(actors).
:- use_module(toplevel_actors, [
       toplevel_spawn/2,
       toplevel_call/2,
       toplevel_call/3,
       toplevel_next/1,
       toplevel_next/2,
       toplevel_stop/1,
       toplevel_abort/1
   ]).
:- use_module(node, []).
:- use_module(rpc, [
       rpc/2,
       rpc/3
   ]).
:- use_module(library(http/thread_httpd)).
:- use_module(library(random)).
                /*******************************
                *             TESTS            *
                *******************************/   
            

:- use_module(library(plunit)).



t :-
   run_tests([ receive,
               actors,
               toplevels,
               node,
               rpc,
               programs,
               parallel
             ]).

:- begin_tests(receive).
   
test(receive1, X == bar) :-
   self(Self),
   Self ! foo(bar),    
   receive({
       foo(X) -> true
   }).

test(receive2, X == baz) :-
   self(Self),
   Self ! not_matching,    
   Self ! foo(bar),    
   receive({
       foo(X) -> true;
       _ -> X = baz
   }),
   receive({
       foo(_) -> true
   }).    

test(receive3, X == baz) :-
   receive({
       foo(X) -> true
   },[
       timeout(1),
       on_timeout(X = baz)
   ]).

test(receive4, X == baz) :-
   receive({
       foo(X) -> true
   },[
       timeout(0),
       on_timeout(X = baz)
   ]).
   
test(receive5, Result == [hello, goodbye]) :-
   self(S),
   S ! hello,
   S ! goodbye,
   receive({A -> true}),
   receive({B -> true}),
   Result = [A,B].
   
test(receive6, X == baz) :-
   self(S),
   S ! foo(baz),    
   receive({
       foo(X) if true, true -> 
           true
   }).

test(receive7, X == a) :-
   self(S),
   S ! foo,    
   receive({
       foo if p(X) -> 
           true
   }). 
   
test(receive8, X == b) :-
   self(S),
   S ! foo(b),    
   receive({
       foo(X) if p(Y), X=Y -> 
           true
   }).        
       
test(receive9, Result = done) :-
   receive({}, [timeout(1)]),
   Result = done.

test(receive10, Result == done) :-
   self(Self),
   Self ! done,
   receive({
       Result -> true ;
       unreachable ->
           Result = wrong
   }).

test(receive11, Result == done) :-
   self(Self),
   (   true
   ;   Self ! foo(stop),
       receive({
          foo(X) -> 
             Self ! X
       })
   ),
   receive({
      stop -> true
   }, [
       timeout(0),
       on_timeout(fail)
   ]),
   Result = done.
   
:- end_tests(receive).


:- begin_tests(actors).


% 13    
test(actors2_exit_1, Reason == reason) :-
   spawn(exit(reason), Pid, [
       monitor(true)
   ]),
   receive({
       down(Pid, _Ref, Reason) -> true
   }).
% 14    
test(actors2_exit_2, Reason == reason) :-
   spawn((repeat, fail), Pid, [
       monitor(true)
   ]),
   exit(Pid, reason),
   receive({
       down(Pid, _Ref, Reason) -> true
   }).
% 15    
test(actors3_register_1, Msg == hello) :-
   self(Pid),
   register(test, Pid),
   test ! hello,
   unregister(test),
   receive({
       Msg -> true
   }).
% 16    
test(actors3_register_2, Reason == reason) :-
   spawn((repeat, fail), Pid, [
      monitor(true)
   ]),
   register(test2, Pid),
   whereis(test2, Pid2),
   exit(Pid2, reason),
   whereis(test2, undefined),
   unregister(test2),
   receive({
       down(Pid2, _Ref, Reason) -> true
   }).
    
:- end_tests(actors).



:- begin_tests(toplevels).

test(shell_call_default_template,
     Answers == [shell_example_p(a), shell_example_p(b)]) :-
   setup_call_cleanup(
       toplevel_spawn(Pid, [
           session(true),
           monitor(true)
       ]),
       (
           toplevel_call(Pid, shell_example_p(_X)),
           receive({
               success(Pid, Answers, false) -> true
           }, [
               timeout(1)
           ])
       ),
       cleanup_toplevel(Pid)
   ).

test(shell_call_template_option, Answers == [a, b]) :-
   setup_call_cleanup(
       toplevel_spawn(Pid, [
           session(true),
           monitor(true)
       ]),
       (
           toplevel_call(Pid, shell_example_p(X), [
               template(X)
           ]),
           receive({
               success(Pid, Answers, false) -> true
           }, [
               timeout(1)
           ])
       ),
       cleanup_toplevel(Pid)
   ).

test(shell_limit_one_then_next, Answers == [[a], [b]]) :-
   setup_call_cleanup(
       toplevel_spawn(Pid, [
           session(true),
           monitor(true)
       ]),
       (
           toplevel_call(Pid, shell_example_p(X), [
               template(X),
               limit(1)
           ]),
           receive({
               success(Pid, [a], true) -> true
           }, [
               timeout(1)
           ]),
           toplevel_next(Pid),
           receive({
               success(Pid, [b], false) -> true
           }, [
               timeout(1)
           ]),
           Answers = [[a], [b]]
       ),
       cleanup_toplevel(Pid)
   ).

test(shell_offset_limit_next_and_stop,
     Answers == [[101,102,103], [104,105,106], [107,108,109,110,111], [true]]) :-
   setup_call_cleanup(
       toplevel_spawn(Pid, [
           session(true),
           monitor(true)
       ]),
       (
           toplevel_call(Pid, between(1, infinite, I), [
               offset(100),
               template(I),
               limit(3)
           ]),
           receive({
               success(Pid, [101,102,103], true) -> true
           }, [
               timeout(1)
           ]),
           toplevel_next(Pid),
           receive({
               success(Pid, [104,105,106], true) -> true
           }, [
               timeout(1)
           ]),
           toplevel_next(Pid, [
               limit(5)
           ]),
           receive({
               success(Pid, [107,108,109,110,111], true) -> true
           }, [
               timeout(1)
           ]),
           toplevel_stop(Pid),
           toplevel_call(Pid, true),
           receive({
               success(Pid, [true], false) -> true
           }, [
               timeout(1)
           ]),
           Answers = [[101,102,103], [104,105,106], [107,108,109,110,111], [true]]
       ),
       cleanup_toplevel(Pid)
   ).

test(shell_output_message, Results == [hello, output(hello)]) :-
   setup_call_cleanup(
       toplevel_spawn(Pid, [
           session(true),
           monitor(true)
       ]),
       (
           toplevel_call(Pid, output(hello)),
           receive({
               output(Pid, hello) -> true
           }, [
               timeout(1)
           ]),
           receive({
               success(Pid, [output(hello)], false) -> true
           }, [
               timeout(1)
           ]),
           Results = [hello, output(hello)]
       ),
       cleanup_toplevel(Pid)
   ).

test(shell_input_roundtrip, Answer == input('Input', hello)) :-
   setup_call_cleanup(
       toplevel_spawn(Pid, [
           session(true),
           monitor(true)
       ]),
       (
           toplevel_call(Pid, input('Input', X)),
           receive({
               prompt(Pid, 'Input') ->
                   respond(Pid, hello)
           }, [
               timeout(1)
           ]),
           receive({
               success(Pid, [input('Input', hello)], false) -> true
           }, [
               timeout(1)
           ]),
           Answer = input('Input', hello),
           X = hello
       ),
       cleanup_toplevel(Pid)
   ).

test(shell_abort_nonterminating_goal, Results == [asserted, resumed]) :-
   setup_call_cleanup(
       toplevel_spawn(Pid, [
           session(true),
           monitor(true)
       ]),
       (
           toplevel_call(Pid, assert((shell_example_loop :- shell_example_loop))),
           receive({
               success(Pid, [assert((shell_example_loop:-shell_example_loop))], false) -> true
           }, [
               timeout(1)
           ]),
           toplevel_call(Pid, shell_example_loop),
           sleep(0.05),
           toplevel_abort(Pid),
           toplevel_call(Pid, true),
           receive({
               success(Pid, [true], false) -> true
           }, [
               timeout(1)
           ]),
           Results = [asserted, resumed]
       ),
       (
           abolish(shell_example_loop/0),
           cleanup_toplevel(Pid)
       )
   ).

:- end_tests(toplevels).


:- begin_tests(node).

test(node_compute_answer_single_slice,
     Answer == success([1,2,3], false)) :-
   setup_call_cleanup(
       retractall(node:cache(_, _, _)),
       node:compute_answer(between(1,3,N), N, 0, 10, Answer),
       retractall(node:cache(_, _, _))
   ).

test(node_compute_answer_cached_paging,
     Answers == [success([1,2], true), success([3,4], true), success([5], false)]) :-
   setup_call_cleanup(
       retractall(node:cache(_, _, _)),
       (
           node:compute_answer(between(1,5,N), N, 0, 2, Answer1),
           node:compute_answer(between(1,5,N), N, 2, 2, Answer2),
           node:compute_answer(between(1,5,N), N, 4, 2, Answer3),
           Answers = [Answer1, Answer2, Answer3]
       ),
       retractall(node:cache(_, _, _))
   ).

test(node_json_not_implemented_message,
     Output == "Content-type: text/plain; charset=UTF-8\n\nJSON output is not yet implemented\nUse format=prolog\n") :-
   with_output_to(string(Output),
                  node:respond_with_answer(json, success([], false))).

:- end_tests(node).


:- begin_tests(rpc).

test(rpc_collects_all_solutions, Solutions == [a,b,c]) :-
   with_test_node(URI,
       findall(X, rpc(URI, member(X, [a,b,c])), Solutions)).

test(rpc_respects_limit_option, Solutions == [1,2,3,4,5]) :-
   with_test_node(URI,
       findall(N, rpc(URI, between(1,5,N), [limit(2)]), Solutions)).

:- end_tests(rpc).


:- begin_tests(programs).


test(program1, Msg == hello) :-
   spawn(echo_server, Pid, [
      monitor(true)
   ]),
   self(Self),
   Pid ! echo(Self, hello),
   receive({Msg -> true}),
   Pid ! echo(Self, hello),
   receive({Msg -> true}),
   exit(Pid, kill),
   receive({
       down(Pid, _Ref, kill) -> true
   }).
  
test(program2, Count == 3) :-
   spawn(count_server(0), Pid, [
      monitor(true)
   ]),
   self(Self),
   Pid ! count(Self),
   receive({Count1 -> true}),
   Pid ! count(Self),
   receive({Count2 -> true}),
   Count is Count1 + Count2,
   Pid ! stop,
   receive({
       down(Pid, _Ref, true) -> true
   }).

test(program3, Messages == [high,high,low,low]) :-
    self(S),
    S ! 15-high, S ! 7-low, S ! 1-low, S ! 17-high,
    important(Messages),
    S ! 15-high, S ! 7-low, S ! 1-low, S ! 17-high,
    important(Messages).
    
test(program4, Response == ok(cheese)) :-
   spawn(fridge([]), Pid, [
       monitor(true)
   ]),
   store(Pid, cheese, ok),
   take(Pid, cheese, Response),
   Pid ! terminate,
   receive({
       down(Pid, _Ref, true) -> true
   }).
    
test(program5, Response == ok(meat)) :-
   spawn(server(fridge, []), Pid, [
       monitor(true)
   ]),
   rpc_synch(Pid, store(meat), ok),
   rpc_synch(Pid, take(meat), Response),
   Pid ! upgrade(fridge),
   rpc_synch(Pid, store(meat), ok),
   rpc_synch(Pid, take(meat), Response),
   Pid ! terminate,
   receive({
       down(Pid, _Ref, true) -> true
   }).

test(program6, Done == true) :-
   ring(12, hello),
   sleep(0.1),
   Done = true.
    
test(program7, Done == true) :-
    ping_pong,
    Done = true.


:- end_tests(programs).


:- begin_tests(parallel).

test(parallel_success, Done == true) :-
    parallel([sleep(0.1),sleep(0.3),sleep(0.2)]),
    Done = true.

test(parallel_failure, Done == true) :-
    \+ parallel([sleep(1),fail,sleep(2)]),
    Done = true.

test(parallel_error, Done == true) :-
    catch(parallel([sleep(1),sleep(a),sleep(2)]),
          Error, true),
    nonvar(Error),
    Done = true.    
    
:- end_tests(parallel).
    
    
                /*******************************
                *        TEST UTILITIES        *
                *******************************/

p(a). p(b). p(c).

mortal(Who) :- human(Who).

human(socrates). 
human(plato).
human(aristotle).



test_links(FooLink, BarLink, BazLink) :-
    spawn(foo(BarLink, BazLink), Pid, [
        link(FooLink)
    ]),
    register(foo, Pid).

foo(BarLink, BazLink) :-
    spawn(bar(BazLink), Pid, [
        link(BarLink)
    ]),
    register(bar, Pid),
    sleep(5).
    
bar(BazLink) :-
    spawn(baz, Pid, [
        link(BazLink)
    ]),
    register(baz, Pid),
    sleep(10). 
    
baz :-
    sleep(15).  

    


echo_server  :-          
   receive({            
      echo(Pid, Msg) ->
         Pid ! Msg,   
         echo_server  
   }).
    
count_server(Count0) :-                            
   receive({                         
      count(From) ->
         Count is Count0 + 1,              
         From ! Count,              
         count_server(Count);
      stop ->
         true       
   }).            

important(Messages) :-
   receive({
      Priority-Message if Priority > 10 ->
         Messages = [Message|MoreMessages],
         important(MoreMessages)
   },[ timeout(0),
       on_timeout(normal(Messages))
   ]).

normal(Messages) :-
   receive({
      _-Message ->
         Messages = [Message|MoreMessages],
         normal(MoreMessages)
   },[ timeout(0),
       on_timeout(Messages=[])
   ]).


fridge(FoodList0) :-
    receive({
        store(From, Food) ->
            self(Self),
            From ! Self-ok,
            fridge([Food|FoodList0]);
        take(From, Food) ->
            self(Self),
            (   select(Food, FoodList0, FoodList)
            ->  From ! Self-ok(Food),
                fridge(FoodList)
            ;   From ! Self-not_found,
                fridge(FoodList0)
            );
        terminate ->
            true
    }).
   
store(Pid, Food, Response) :-
    self(Self),
    Pid ! store(Self, Food),
    receive({
        Pid-Response -> true
    }).
 
take(Pid, Food, Response) :-
    self(Self),
    Pid ! take(Self, Food),
    receive({
        Pid-Response -> true
    }).


server(Pred, State0) :-
    receive({
        rpc(From, Ref, Request) ->
            call(Pred, Request, State0, Response, State),
            From ! Ref-Response,
            server(Pred, State);
        upgrade(Pred1) ->
            server(Pred1, State0);
        terminate ->
            true
    }).

fridge(store(Food), FoodList, ok, [Food|FoodList]).
fridge(take(Food), FoodList, ok(Food), FoodListRest) :-
    select(Food, FoodList, FoodListRest), !.
fridge(take(_Food), FoodList, not_found, FoodList).

rpc_synch(To, Request, Response) :-
    self(Self),
    make_ref(Ref),
    To ! rpc(Self, Ref, Request),
    receive({
        Ref-Response -> true
    }).
   

% ring(12, hello).

ring(NumberProcesses, Message) :-
   spawn(create(NumberProcesses, Message)).
   
create(NumberProcesses, Message) :-
   self(Self),
   create(NumberProcesses, Self, Message).

create(1, NextProcess, Message) :- !,
   self(Self),
   format("Process ~p connected with ~p~n", [Self, NextProcess]),
   format("Process ~p injects message ~p~n", [Self, Message]),
   NextProcess ! Message.
create(NumberProcesses, NextProcess, Message) :-
   spawn(loop(NextProcess), Prev, [
       link(true)
   ]),
   format("Process ~p created and connected with ~p~n", [Prev, NextProcess]),
   NumberProcesses1 is NumberProcesses - 1,
   create(NumberProcesses1, Prev, Message).

loop(NextProcess) :-
   receive({
      Msg ->
         format("Got message ~p, passing it to ~p~n", [Msg, NextProcess]),
         NextProcess ! Msg
    }).


ping(0, Pong_Pid) :-
    Pong_Pid ! finished,
    format('Ping finished~n',[]).
ping(N, Pong_Pid) :-
    self(Self),
    Pong_Pid ! ping(Self),
    receive({
        pong -> 
            format('Ping received pong~n',[])
    }),
    N1 is N - 1,
    ping(N1, Pong_Pid).
    
pong :-
    receive({
        finished ->
            format('Pong finished~n',[]);
        ping(Ping_Pid) ->
            format('Pong received ping~n',[]),
            Ping_Pid ! pong,
            pong
    }).
    
ping_pong :-
    spawn(pong, Pong_Pid),
    spawn(ping(3, Pong_Pid), Ping_Pid, [
        monitor(true)
    ]),
    receive({
       down(Ping_Pid, _Ref, true) ->
          true
    }).

% ping-pong for benchmarking send and receive  
    
bm_ping(0, Pong_Pid) :-
    Pong_Pid ! finished.
bm_ping(N, Pong_Pid) :-
    self(Self),
    Pong_Pid ! ping(Self),
    receive({
        pong -> true
    }),
    N1 is N - 1,
    bm_ping(N1, Pong_Pid).
    
bm_pong :-
    receive({
        finished -> true;
        ping(Ping_Pid) ->
            Ping_Pid ! pong,
            bm_pong
    }).
    
bm_ping_pong(N) :-
    spawn(bm_pong, Pong_Pid),
    spawn(bm_ping(N, Pong_Pid), Ping_Pid, [
        monitor(true)
    ]),
    receive({
       down(Ping_Pid, _Ref, true) ->
          true
    }).

% Parallel rpc


parallel_rpc(Pids, Request, Responses) :-
    self(Self),
    maplist(par_rpc_aux(Self, Request), Pids, Refs),
    maplist(yield2, Refs, Responses).

par_rpc_aux(Self, Request, Pid, Ref) :-
    make_ref(Ref),
    spawn((rpc_synch(Pid, Request, Response), 
           Self ! Ref-Response)).    

yield2(Ref, Response) :-        
    receive({Ref-Response -> true}).
        


restarter(Init, Name, Count) :-
   spawn(restarter_loop(Init, Name, Count), _, [
      monitor(true)
   ]).

restarter_loop(Init, Name, Count0) :-
   spawn(Init, Pid, [
      monitor(true)
   ]),
   register(Name, Pid),
   receive({
      down(Pid, _, true) ->
         true ;
      down(Pid, _, normal) ->
         writeln('normal shutdown received') ; 
      down(Pid, _, _Anything) ->
         (   Count0 == 0
         ->  true
         ;   Count is Count0 - 1,
             restarter_loop(Init, Name, Count)
         )
    }).


search(Template, Goal, Pid) :-
    search(Template, Goal, Pid, []).
    
search(Template, Goal, Pid, Options) :-
    self(Self),
    spawn(goal(Template, Goal, Pid, Self), Pid,  [
          monitor(true)
        | Options
    ]).
    
goal(Template, Goal, Pid, Parent) :-
    call_cleanup(Goal, Det=true),
    (   var(Det)
    ->  Parent ! success(Pid, Template, true),
        receive({
            next -> fail ;
            stop ->
                Parent ! stopped(Pid)
        })
    ;   Parent ! success(Pid, Template, false)
    ).
   

    
% Benchmarking -- see p. 106 in Erlang Programming

start(Num) :-
    self(Self),
    start_proc(Num, Self).
        
start_proc(0, Pid) :- !,
    Pid ! ok.
start_proc(Num, Pid) :-
    Num1 is Num-1,
    spawn(start_proc(Num1, Pid), NPid),
    NPid ! ok,
    receive({ok -> true}).
    

% A bigger program
    
sleep :-
    Time is random_float/10,
    sleep(Time).

doForks(ForkList) :-
    receive({
        {grabforks, {Left, Right}} ->
            subtract(ForkList, [Left,Right], ForkList1),
            doForks(ForkList1);
        {releaseforks, {Left, Right}} -> 
            doForks([Left, Right| ForkList]);
        {available, {Left, Right}, Sender} ->
            (   member(Left, ForkList),
                member(Right, ForkList)
            ->  Bool = true
            ;   Bool = false
            ),
            Sender ! {areAvailable, Bool},
            doForks(ForkList);
        {die} -> 
            format("Forks put away.~n")
    }).

areAvailable(Forks, Have) :-
    self(Self),
    forks ! {available, Forks, Self},
    receive({
        {areAvailable, false} ->
            Have = false;
        {areAvailable, true} -> 
            Have = true
    }).

processWaitList([], false).
processWaitList([H|T], Result) :-
    {Client, Forks} = H,
    areAvailable(Forks, Have),
    (   Have == true
    ->  Client ! {served},
        Result = true
    ;   Have == false
    ->  processWaitList(T, Result)
    ).

doWaiter([], 0, 0, false) :-
    forks ! {die},
    format("Waiter is leaving.~n"),
    diningRoom ! {allgone}.
doWaiter(WaitList, ClientCount, EatingCount, Busy) :-
    receive({
        {waiting, Client} ->
            WaitList1 = [Client|WaitList], % add to waiting list
            (   Busy == false,
                EatingCount < 2
            ->  processWaitList(WaitList1, Busy1)
            ;   Busy1 = Busy
            ),
            doWaiter(WaitList1, ClientCount, EatingCount, Busy1);
        {eating, Client} ->
            subtract(WaitList, [Client], WaitList1),
            EatingCount1 is EatingCount+1,
            doWaiter(WaitList1, ClientCount, EatingCount1, false);
        {finished} ->
            processWaitList(WaitList, R1),
            EatingCount1 is EatingCount-1,
            doWaiter(WaitList, ClientCount, EatingCount1, R1) ;
        {leaving} ->
            ClientCount1 is ClientCount - 1,
            flag(left_received, N, N+1),
            doWaiter(WaitList, ClientCount1, EatingCount, Busy)
    }).

philosopher(Name, _Forks, 0) :-
    format("~s is leaving.~n", [Name]),
    waiter ! {leaving},
    flag(left, N, N+1).
philosopher(Name, Forks, Cycle) :-
    self(Self),
    format("~s is thinking (cycle ~w).~n", [Name, Cycle]),
    sleep,
    format("~s is hungry (cycle ~w).~n", [Name, Cycle]),
    waiter ! {waiting, {Self, Forks}}, % sit at table
    receive({
        {served} -> 
            forks ! {grabforks, Forks}, % grab forks
            waiter ! {eating, {Self, Forks}}, % start eating
            format("~s is eating (cycle ~w).~n", [Name, Cycle])
    }),
    sleep,
    forks ! {releaseforks, Forks}, % put forks down
    waiter ! {finished},
    Cycle1 is Cycle - 1,
    philosopher(Name, Forks, Cycle1).

dining :-    
    AllForks = [1, 2, 3, 4, 5],
    Clients = 5,
    self(Self),
    register(diningRoom, Self),
    spawn(doForks(AllForks), ForksPid),
    register(forks, ForksPid),
    spawn(doWaiter([], Clients, 0, false), WaiterPid),
    register(waiter, WaiterPid),
    Life_span = 20,
    spawn(philosopher('Aristotle', {5, 1}, Life_span)),
    spawn(philosopher('Kant', {1, 2}, Life_span)),
    spawn(philosopher('Spinoza', {2, 3}, Life_span)),
    spawn(philosopher('Marx', {3, 4}, Life_span)),
    spawn(philosopher('Russel', {4, 5}, Life_span)),
    receive({
        {allgone} -> 
            format("Dining room closed.~n")
    }),
    unregister(diningRoom),
    unregister(forks), 
    unregister(waiter).
    
    
% parallel/1    

parallel(Goals) :-
    maplist(par_call, Goals, Pids),
    maplist(par_yield(Pids), Pids, Goals).
    
par_call(Goal, Pid) :- 
    self(Self),
    spawn((call(Goal), Self ! Pid-Goal), Pid, [
        monitor(true)
    ]).

par_yield(Pids, Pid, Goal) :-
    receive({
        down(Pid, _, true) -> 
            true ;
        down(_, _, false) ->
            tidy_up_all(Pids),
            !, fail ;
        down(_, _, exception(E)) ->
            tidy_up_all(Pids),
            throw(E)
    }),
    receive({Pid-Goal -> true}).


tidy_up_all(Pids) :-
    maplist(tidy_up, Pids).
    
tidy_up(Pid) :-
    demonitor(Pid), 
    exit(Pid, kill),
    mailbox_rm(Pid).

mailbox_rm(Pid) :-
    receive({
        Msg if arg(1, Msg, Pid) ->
            mailbox_rm(Pid)
    },[
        timeout(0)
    ]).



test :-
    Goal = (sleep(1),sleep(3),sleep(2)),
    format("Running ~p~n",[Goal]),
    time(Goal), 
    fail.
test :-
    Goal = parallel([sleep(1),sleep(3),sleep(2)]),
    format("Running ~p~n",[Goal]),
    time(Goal),
    fail.
test :-
    Goal = parallel([sleep(1),fail,sleep(2)]),
    format("Running ~p~n",[Goal]),    
    (   time(Goal)
    ->  writeln('Error: Should not have succeeded')
    ;   writeln('Failed, as it should'),
        fail
    ).
test :-
    Goal = parallel([sleep(1),(sleep(3),fail),sleep(2)]),
    format("Running ~p~n",[Goal]),    
    (   time(Goal)
    ->  writeln('Error: Should not have succeeded')
    ;   writeln('Also failed, as it should, although it takes longer'),
        fail
    ).
test :-
    Goal = parallel([sleep(1),sleep(a),sleep(2)]),
    format("Running ~p~n",[Goal]),    
    catch(time(Goal), Error, true), 
    writeln('Error': Error),
    fail.
test :-
    writeln('Now, no more messages should be seen below.'),   
    flush.


cleanup_toplevel(Pid) :-
    exit(Pid, kill),
    receive({
        down(Pid, _Ref, kill) -> true
    }, [
        timeout(1),
        on_timeout(true)
    ]),
    drain_toplevel_messages(Pid).

drain_toplevel_messages(Pid) :-
    receive({
        Msg if compound(Msg), arg(1, Msg, Pid) ->
            drain_toplevel_messages(Pid)
    }, [
        timeout(0)
    ]).


shell_example_p(a).
shell_example_p(b).


with_test_node(URI, Goal) :-
    random_between(20000, 45000, Port),
    setup_call_cleanup(
        node:node(Port),
        (
            format(atom(URI), 'http://127.0.0.1:~w', [Port]),
            call(Goal)
        ),
        http_stop_server(Port, [])
    ).

  
