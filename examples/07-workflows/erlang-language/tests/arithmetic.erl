-module(arithmetic).
-export([main/0, add/2]).

add(X, Y) -> X + Y.

main() -> io:format("~p~n", [add(20, 22)]).
