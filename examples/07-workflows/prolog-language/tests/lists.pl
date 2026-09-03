% member/2 is written in the language itself, not implemented as a builtin.
member(X, [X | _]).
member(X, [_ | Tail]) :-
    member(X, Tail).

?- member(X, [1, 2, 3]).
?- [Head | Tail] = [1, 2, 3].
