-module(tuple_pattern).
-export([main/0, value/1]).

value({ok, X}) -> X;
value(_) -> 0.

main() -> io:format("~p~n", [value({ok, 42})]).
