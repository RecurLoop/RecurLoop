data Maybe a = Nothing | Just a
fromMaybe d Nothing = d
fromMaybe _ (Just x) = x
main = print (fromMaybe 0 (Just 42))
