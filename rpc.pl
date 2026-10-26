:- module(rpc,
       [ rpc/2,                  % +URI, +Goal
         rpc/3                   % +URI, +Goal, +Options
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
:- use_module(term_wire).


%!  rpc(+URI, +Goal) is nondet.
%!  rpc(+URI, +Goal, +Options) is nondet.
%
%   Call Goal against the node identified by URI. Solutions are returned
%   to the caller one at a time on backtracking. Options:
%
%     - limit(+Positive)
%       Maximum number of solutions to fetch in each HTTP request.
%       Default: all solutions in one response.
%
%   Any additional options are passed to http_open/3.

rpc(URI, Goal) :-
    rpc(URI, Goal, []).

rpc(URI, Goal0, Options) :-
    strip_module(Goal0, _, Goal),
    portable_term(Goal),
    parse_url(URI, Parts),
    term_variables(Goal, Vars), Template =.. [v|Vars],
    variable_names(Vars, 0, Names),
    term_atom(Names, Goal, GA), term_atom(Names, Template, TA),
    (select_option(limit(Limit), Options, HTTPOptions)
    -> must_be(positive_integer, Limit), Limits=[limit=Limit]
    ; HTTPOptions=Options, Limits=[]),
    rpc_page(Template, 0, GA, TA, Parts, Limits, HTTPOptions).

rpc_page(Template, Offset, GA, TA, Parts, Limits, Options) :-
    parse_url(ExpandedURI, [path('/call'),
        search([goal=GA,template=TA,offset=Offset,format=prolog|Limits])|Parts]),
    setup_call_cleanup(http_open(ExpandedURI, Stream, Options),
        read_term(Stream, Answer, [double_quotes(chars)]), close(Stream)),
    portable_term(Answer),
    rpc_answer(Answer, Template, Offset, GA, TA, Parts, Limits, Options).

rpc_answer(success(Slice,More), Template, Offset, GA, TA, Parts, Limits, Options) :-
    is_list(Slice), (More == true; More == false), !,
    (member(Template, Slice)
    ; More == true, Slice \== [], length(Slice, Count), Next is Offset+Count,
      rpc_page(Template, Next, GA, TA, Parts, Limits, Options)).
rpc_answer(failure, _, _, _, _, _, _, _) :- !, fail.
rpc_answer(error(E), _, _, _, _, _, _, _) :- !, throw(E).
rpc_answer(Answer, _, _, _, _, _, _, _) :- domain_error(answer_term, Answer).
