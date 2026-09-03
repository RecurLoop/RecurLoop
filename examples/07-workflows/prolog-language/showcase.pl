% RecurLoop Prolog language compatibility showcase.
%
% This is ordinary Prolog-style source. The imported RecurLoop language image
% supplies the parser and logic runtime; the C++ host has no Prolog-specific
% parser, unifier or backtracking engine.

parent(tom, bob).
parent(bob, ann).
parent(bob, pat).
parent(pat, jim).

ancestor(X, Y) :-
    parent(X, Y).
ancestor(X, Y) :-
    parent(X, Z),
    ancestor(Z, Y).

member(X, [X | _]).
member(X, [_ | Tail]) :-
    member(X, Tail).

choice(a).
choice(b).
pair(X, Y) :-
    choice(X),
    choice(Y).

% Recursive relation: four answers, reached through clause-order DFS.
?- ancestor(tom, X).

% Lists plus recursion: three answers.
?- member(Item, [1, 2, 3]).

% Pure structural unification, no predicate lookup required.
?- point(X, 2) = point(1, Y).

% Trail rollback across nested choice points.
?- pair(Left, Right).

% Ground success and failure.
?- parent(tom, bob).
?- parent(ann, tom).
