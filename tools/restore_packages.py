#!/usr/bin/env python3
"""Restore versioned data from reviewed repository chunks; never execute their contents."""
from pathlib import Path
import argparse,hashlib,json
ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('--font-only',action='store_true');a=p.parse_args()
 manifest=json.loads((ROOT/'downloads/preview-manifest.json').read_text())
 for item in manifest['packages']:
  if a.font_only and item['id']!='font':continue
  target=ROOT/item['output'];target.parent.mkdir(parents=True,exist_ok=True)
  if target.exists() and hashlib.sha256(target.read_bytes()).hexdigest()==item['sha256']:continue
  digest=hashlib.sha256()
  with target.open('wb') as out:
   for part in item['parts']:
    data=(ROOT/part).read_bytes();digest.update(data);out.write(data)
  if digest.hexdigest()!=item['sha256']:target.unlink();raise SystemExit('Hash mismatch: '+item['id'])
  print('Restored:',item['output'])
if __name__=='__main__':main()
