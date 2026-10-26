:- module(term_wire, [portable_term/1, term_atom/3, variable_names/3,
                      parse_goal_template/4, goal_key/2, safe_answer/2]).

% The wire language contains ordinary acyclic terms and character-list text.
portable_term(Term) :-
    (acyclic_term(Term) -> true; representation_error(cyclic_term)),
    term_attvars(Term, Attrs),
    (Attrs == [] -> true; representation_error(constraints)),
    plain_term(Term).

plain_term(Term) :- var(Term), !.
plain_term([]) :- !.
plain_term(Term) :- (atom(Term); number(Term)), !.
plain_term(Term) :- compound(Term), !,
    compound_name_arguments(Term, _, Args), maplist(plain_term, Args).
plain_term(_) :- representation_error(transportable_term).

safe_answer(Candidate, Answer) :-
    catch((portable_term(Candidate), Answer = Candidate), E, Answer = error(E)).

variable_names([], _, []).
variable_names([Var|Vars], N, [Name=Var|Names]) :-
    format(atom(Name), 'V~d', [N]),
    N1 is N+1, variable_names(Vars, N1, Names).

term_atom(Names, Term, Atom) :-
    portable_term(Term),
    with_output_to(atom(Atom),
        write_term(Term, [quoted(true), ignore_ops(true),
                         variable_names(Names), numbervars(false),
                         portray(false)])).

% Numbered variable *names*, rather than '$VAR'/1 data, give an injective key.
goal_key(Input, Key) :-
    term_variables(Input, Vars), variable_names(Vars, 0, Names),
    term_atom(Names, Input, Key).

parse_goal_template(GoalAtom, TemplateAtom, Goal, Template) :-
    atomic_list_concat(['(',GoalAtom,')+(',TemplateAtom,')'], Text),
    read_term_from_atom(Text, Goal+Template,
                        [syntax_errors(error), double_quotes(chars)]),
    portable_term(Goal-Template).
