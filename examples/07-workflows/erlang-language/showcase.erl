-module(recurloop_erlang_showcase).
-export([main/0, worker/0, sum/2]).

sum(0, Acc) -> Acc;
sum(N, Acc) -> sum(N - 1, Acc + N).

worker() ->
    receive
        {compute, From, N} ->
            From ! ignored,
            From ! {result, sum(N, 0)}
    end.

main() ->
    Worker = spawn(fun worker/0),
    Worker ! {compute, self(), 10},
    receive
        {result, Value} -> io:format("result=~p~n", [Value])
    end,
    receive
        ignored -> io:format("mailbox-preserved~n")
    end.
