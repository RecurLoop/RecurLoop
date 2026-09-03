ones = 1 : ones
takeList 0 _ = []
takeList n (x:xs) = x : takeList (n - 1) xs
main = print (takeList 5 ones)
