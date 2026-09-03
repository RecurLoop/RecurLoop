-module(badmatch).
-export([main/0]).

main() -> X = 1, X = 2.
