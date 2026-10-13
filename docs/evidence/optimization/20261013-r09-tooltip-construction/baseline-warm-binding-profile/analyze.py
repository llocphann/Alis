from pathlib import Path
import xml.etree.ElementTree as ET
from collections import defaultdict
import json
p=Path(__file__).parent
meta={};stats=defaultdict(lambda:{'count':0,'inclusiveNs':0,'maxNs':0,'minStart':None,'maxEnd':None});bounds={};invalid=[]
for ev,e in ET.iterparse(p/'warm-motion.qtd',events=['start','end']):
 if ev=='start' and e.tag=='trace':bounds=dict(e.attrib)
 if ev=='end' and e.tag=='event':
  meta[int(e.attrib['index'])]={child.tag:child.text for child in e};e.clear()
 if ev=='end' and e.tag=='range':
  a=e.attrib
  if 'duration' in a:
   d=int(a['duration']);start=int(a['startTime']);idx=int(a['eventIndex']);s=stats[idx]
   if d<0 or d>30_000_000_000:invalid.append(dict(a))
   s['count']+=1;s['inclusiveNs']+=d;s['maxNs']=max(d,s['maxNs']);s['minStart']=start if s['minStart'] is None else min(start,s['minStart']);s['maxEnd']=start+d if s['maxEnd'] is None else max(start+d,s['maxEnd'])
  e.clear()
ranking=sorted([{'event':k,**meta.get(k,{}),**v}for k,v in stats.items()],key=lambda a:a['inclusiveNs'],reverse=True)
(p/'analysis.json').write_text(json.dumps({'traceHeader':bounds,'invalidDurations':invalid[:20],'eventTypes':dict(__import__('collections').Counter(v.get('type') for v in meta.values())),'ranking':ranking},indent=2))
print('HEADER',bounds,'INVALID',len(invalid),'EVENTS',len(meta),'RANGES',sum(s['count']for s in stats.values()))
for x in ranking[:35]:print(x.get('type'),x.get('displayname'),x.get('details',''),x['count'],round(x['inclusiveNs']/1e6,2),'ms inclusive',round(x['maxNs']/1e6,2),'ms max')
