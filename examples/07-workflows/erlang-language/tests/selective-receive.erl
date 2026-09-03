-module(selective_receive).
-export([main/0, worker/0]).

worker() ->
    receive
        {start, From} -> From ! noise, From ! {answer, 42}
    end.

main() ->
    Worker = spawn(fun worker/0),
    Worker ! {start, self()},
    receive
        {answer, Value} -> io:format("answer=~p~n", [Value])
    end,
    receive
        noise -> io:format("noise~n")
    end.
