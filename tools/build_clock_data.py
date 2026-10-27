#!/usr/bin/env python3
"""Build small offline clock tables from reviewed IANA tzdata and CLDR city names.
No model or network needed at runtime. Downloaded build inputs stay outside the repo.
"""
import argparse,datetime as dt,hashlib,json,re,subprocess,tarfile,tempfile,unicodedata,xml.etree.ElementTree as ET
from pathlib import Path
from zoneinfo import ZoneInfo
ROOT=Path(__file__).resolve().parents[1]
START=1577836800 # 2020-01-01 UTC
END=2082758400 # 2036-01-01 UTC
def normalize(text):return ''.join(c for c in unicodedata.normalize('NFC',text.lower().replace('ё','е')) if c.isalnum())
def build(source):
 archive=source/'tzdata2026e.tar.gz'
 names=['africa','antarctica','asia','australasia','europe','northamerica','southamerica','etcetera','backward']
 with tempfile.TemporaryDirectory(prefix='leemon-clock-') as temporary:
  temporary=Path(temporary);out=temporary/'zones'
  with tarfile.open(archive) as tar:
   version=tar.extractfile('version').read().decode().strip()
   assert version=='2026e'
   for name in names:(temporary/name).write_bytes(tar.extractfile(name).read())
   license_text=tar.extractfile('LICENSE').read()
  subprocess.run(['zic','-d',str(out),*[str(temporary/name) for name in names]],check=True)
  zones={};aliases={}
  def alias(name,zone):
   key=normalize(name)
   if key:aliases.setdefault(key,[]).append(zone)
  for path in sorted(out.rglob('*')):
   if not path.is_file():continue
   name=path.relative_to(out).as_posix()
   with path.open('rb') as f:zone=ZoneInfo.from_file(f,key=name)
   def offset(stamp):return int(dt.datetime.fromtimestamp(stamp,dt.timezone.utc).astimezone(zone).utcoffset().total_seconds())
   transitions=[[START,offset(START)]]
   stamp=START
   while stamp<END:
    next_stamp=min(END,stamp+86400)
    previous=transitions[-1][1];following=offset(next_stamp)
    if following!=previous:
     low=stamp;high=next_stamp
     while high-low>1:
      mid=(low+high)//2
      if offset(mid)==previous:low=mid
      else:high=mid
     transitions.append([high,following])
    stamp=next_stamp
   zones[name]={'transitions':transitions}
   alias(name,name)
   if '/' in name:alias(name.rsplit('/',1)[1].replace('_',' '),name)
  for locale in ['root','en','ru','zh']:
   tree=ET.parse(source/f'cldr-{locale}.xml')
   for node in tree.findall('.//timeZoneNames/zone'):
    name=node.attrib.get('type','');city=node.find('exemplarCity')
    if name in zones and city is not None and city.text and city.text!='↑↑↑':alias(city.text,name)
  extra={
   'Europe/Moscow':['Москва','Москве','Воронеж','Воронеже','Voronezh','沃罗涅日'],
   'Asia/Shanghai':['Пекин','Пекине','Beijing','北京'],
   'Europe/London':['Лондоне'], 'Asia/Tokyo':['Токио'], 'America/New_York':['Нью-Йорке','Washington','Вашингтон','Вашингтоне','华盛顿'],
   'America/Los_Angeles':['San Francisco','Сан-Франциско','旧金山'], 'Europe/Paris':['Париже'],
   'Europe/Berlin':['Берлине'], 'Asia/Dubai':['Дубае'], 'Europe/Minsk':['Минске'],
   'Europe/Kyiv':['Киеве'], 'Asia/Novosibirsk':['Новосибирске'], 'Asia/Yekaterinburg':['Екатеринбурге'],
   'UTC':['UTC','GMT','世界时']}
  for zone,names_ in extra.items():
   for name in names_:alias(name,zone)
  aliases={key:sorted(set(values)) for key,values in aliases.items()}
  # Equivalent old IANA aliases must not create a false ambiguity.
  for key,values in aliases.items():
   distinct=[]
   for name in values:
    if not any(zones[name]==zones[other] for other in distinct):distinct.append(name)
   aliases[key]=distinct
  result={'schema_version':1,'tzdb_version':version,'valid_from':START,'valid_until':END,'zones':zones,'aliases':aliases}
  dest=ROOT/'config/world_clock.json';dest.write_text(json.dumps(result,ensure_ascii=False,separators=(',',':'))+'\n')
  (ROOT/'legal/upstream/IANA-tzdata-LICENSE.txt').write_bytes(license_text)
  (ROOT/'legal/upstream/CLDR-LICENSE.txt').write_bytes((source/'CLDR-LICENSE').read_bytes())
  receipt={'iana':'https://data.iana.org/time-zones/releases/tzdata2026e.tar.gz','cldr':'https://github.com/unicode-org/cldr/tree/release-48','input_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(source.iterdir()) if p.is_file()},'zone_count':len(zones),'alias_count':len(aliases),'output_sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),'data_bytes':dest.stat().st_size,'rights':'IANA public domain data; CLDR Unicode License V3 notices included'}
  (ROOT/'manifests/world_clock_sources.json').write_text(json.dumps(receipt,indent=2)+'\n')
  print(json.dumps(receipt))
if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--source',type=Path,required=True);build(parser.parse_args().source)
