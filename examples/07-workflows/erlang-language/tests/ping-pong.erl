-module(ping_pong).
-export([main/0, pong/0]).

pong() ->
    receive
        {ping, From} -> From ! pong
    end.

main() ->
    Pong = spawn(fun pong/0),
    Pong ! {ping, self()},
    receive
        pong -> io:format("pong~n")
    end.
