# builds a "bumped" bar
def build_bumped(gradient):
 ret = []
 rret = []
 for i in range(0, len(gradient)-1):
  tmp = []
  if i==0:
   tmp.append(gradient[0])
  elif i==1:
   tmp.append(gradient[1])
   tmp.append(gradient[0])
  elif i<len(gradient)-1:
   tmp.append(gradient[i+1])
   for j in range(0, i-1):
    tmp.append(gradient[i])
   tmp.append(gradient[i-1])
  tmp.append(0)
  for i in range(0, len(tmp)):
    ret.append(tmp[i])
    rret.insert(0, tmp[len(tmp)-1-i])
 tmp = []
 tmp.append(gradient[-2])
 for j in range(0, len(gradient)):
  tmp.append(gradient[-1])
 tmp.append(0)
 return ret + tmp + rret

print(build_bumped([6,14,15,3,13,7,1]))