% Four Cartesian-product solutions require binding rollback between branches.
choice(a).
choice(b).
pair(X, Y) :-
    choice(X),
    choice(Y).

?- pair(X, Y).
