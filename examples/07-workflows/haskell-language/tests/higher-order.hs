mapList f [] = []
mapList f (x:xs) = f x : mapList f xs
double x = x * 2
main = print (mapList double [1,2,3])
