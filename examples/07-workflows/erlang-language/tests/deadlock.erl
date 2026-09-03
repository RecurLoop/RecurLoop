-module(deadlock).
-export([main/0]).

main() -> receive never -> ok end.
