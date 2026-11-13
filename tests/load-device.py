#!/usr/bin/env python3
import concurrent.futures,json,time,urllib.request
end=time.monotonic()+60
opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
def run(_):
 size=0; errors=0
 while time.monotonic()<end:
  try:
   with opener.open('http://198.18.77.1:18002/load',timeout=10) as response:
    while time.monotonic()<end:
     block=response.read(65536)
     if not block: break
     size+=len(block)
  except Exception: errors+=1
 return {'bytes':size,'errors':errors}
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
 result=list(pool.map(run,range(8)))
print(json.dumps({'streams':8,'seconds':60,'bytes':sum(x['bytes'] for x in result),'errors':sum(x['errors'] for x in result)}))
