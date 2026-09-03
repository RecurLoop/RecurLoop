-- RecurLoop Haskell-language stress test.
-- This file uses ordinary Haskell surface syntax for the supported subset.

data Maybe a = Nothing | Just a

factorial 0 = 1
factorial n = n * factorial (n - 1)

add x y = x + y
inc = add 1

fromMaybe d Nothing = d
fromMaybe _ (Just x) = x

ones = 1 : ones
takeList 0 _ = []
takeList n (x:xs) = x : takeList (n - 1) xs
headOr d [] = d
headOr _ (x:_) = x

score = factorial 5 + inc 41 + fromMaybe 0 (Just 42) + headOr 0 (takeList 1 ones)

main :: IO ()
main = print score
