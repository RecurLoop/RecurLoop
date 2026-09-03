% Recursive ancestry exercises fresh clause variables and recursive DFS.
parent(tom, bob).
parent(bob, ann).
parent(bob, pat).
parent(pat, jim).

ancestor(X, Y) :-
    parent(X, Y).
ancestor(X, Y) :-
    parent(X, Z),
    ancestor(Z, Y).

?- ancestor(tom, X).
