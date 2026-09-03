-module(main_before_worker).
-export([main/0, worker/0]).

main() ->
    Pid = spawn(fun worker/0),
    Pid ! {hello, self()},
    receive
        ok -> io:format("ok~n")
    end.

worker() ->
    receive
        {hello, From} -> From ! ok
    end.
