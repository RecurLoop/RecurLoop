-module(function_clauses).
-export([main/0, sum/2]).

sum(0, Acc) -> Acc;
sum(N, Acc) -> sum(N - 1, Acc + N).

main() -> io:format("~p~n", [sum(100, 0)]).
