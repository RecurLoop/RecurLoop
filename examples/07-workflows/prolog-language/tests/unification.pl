% Repeated variables must denote the same logical variable.
?- point(X, 2) = point(1, Y).
?- same(X, X) = same(alpha, alpha).
?- same(X, X) = same(alpha, beta).
