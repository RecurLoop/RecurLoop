-module(mailbox_recursion).
-export([main/0, worker/0, second/1]).

worker() ->
    receive
        {first, From} -> From ! one, second(From)
    end.

second(From) ->
    receive
        second -> From ! two
    end.

main() ->
    Pid = spawn(fun worker/0),
    Pid ! {first, self()},
    Pid ! second,
    receive one -> io:format("one~n") end,
    receive two -> io:format("two~n") end.
