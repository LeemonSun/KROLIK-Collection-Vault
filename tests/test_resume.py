"""Offline recovery must be deterministic and preserve unknown edits."""
import base64,io,json,sys,tempfile,unittest,zipfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import resume
class RecoveryTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
  self.base=Path(self.tmp.name);self.source=self.base/'source';self.source.mkdir()
  (self.source/'AGENTS.md').write_text('Привет / English / 中文\n')
  (self.source/'image.png').write_bytes(b'not a real image')
  (self.source/'downloads').mkdir();(self.source/'downloads/a.chunk').write_text('excluded')
  self.index=resume.make_capsule(self.source)
  self.raw=base64.b64decode((self.source/'recovery/source_capsule.b64').read_text())
  self.dest=self.base/'empty'
 def restore(self,**kw):return resume.restore(self.dest,self.raw,resume.sha(self.raw),**kw)
 def test_deterministic_small_source_only(self):
  self.assertEqual(self.index,resume.make_capsule(self.source))
  with zipfile.ZipFile(io.BytesIO(self.raw)) as z:
   self.assertEqual(set(z.namelist()),{'AGENTS.md','_CAPSULE_INDEX.json'})
 def test_large_capsule_parts_roundtrip(self):
  import random,string
  rng=random.Random(17)
  (self.source/'large.txt').write_text(''.join(rng.choices(string.ascii_letters+string.digits,k=650000)))
  index=resume.make_capsule(self.source)
  self.assertEqual(index['schema_version'],2)
  encoded=''.join((self.source/name).read_text().strip() for name in index['capsule_parts'])
  self.assertTrue(all((self.source/name).stat().st_size<500000 for name in index['capsule_parts']))
  raw=base64.b64decode(encoded)
  self.assertEqual(resume.sha(raw),index['capsule_sha256'])
  self.assertEqual(resume.make_capsule(self.source),index)
  result=resume.restore(self.dest,raw,index['capsule_sha256'])
  self.assertEqual(set(result['written']),{'AGENTS.md','large.txt'})
 def test_empty_then_idempotent(self):
  self.assertEqual(self.restore()['written'],['AGENTS.md'])
  self.assertEqual(self.restore()['written'],[])
 def test_known_old_version_updated(self):
  self.dest.mkdir();old=b'old source';(self.dest/'AGENTS.md').write_bytes(old)
  self.assertEqual(self.restore(known={'AGENTS.md':[resume.gitsha(old)]})['written'],['AGENTS.md'])
 def test_unknown_edit_preserved(self):
  self.dest.mkdir();(self.dest/'AGENTS.md').write_text('my edit')
  self.assertEqual(self.restore()['conflicts'],['AGENTS.md'])
  self.assertEqual((self.dest/'AGENTS.md').read_text(),'my edit')
 def test_edit_after_restore_preserved(self):
  self.restore();(self.dest/'AGENTS.md').write_text('new edit')
  self.assertEqual(self.restore()['conflicts'],['AGENTS.md'])
 def test_receipt_allows_next_update(self):
  self.restore();(self.source/'AGENTS.md').write_text('next revision');resume.make_capsule(self.source)
  self.raw=base64.b64decode((self.source/'recovery/source_capsule.b64').read_text())
  self.assertEqual(self.restore()['written'],['AGENTS.md'])
 def test_corrupt_capsule_writes_nothing(self):
  with self.assertRaises(ValueError):resume.restore(self.dest,self.raw+b'bad',resume.sha(self.raw))
  self.assertFalse(self.dest.exists())
 def test_unsafe_paths(self):
  for p in ['.','../escape','/absolute','C:/x','a\\b','.git/config']:
   with self.subTest(path=p),self.assertRaises(ValueError):resume.safe_path(self.dest,p)
 def test_symlink_escape(self):
  self.dest.mkdir();(self.dest/'outside').symlink_to(self.source,target_is_directory=True)
  with self.assertRaises(ValueError):resume.safe_path(self.dest,'outside/AGENTS.md')
 def test_malicious_manifest_no_partial_write(self):
  files={'valid.txt':b'ok','../escape':b'bad'};stream=io.BytesIO()
  with zipfile.ZipFile(stream,'w') as z:
   for n,d in files.items():z.writestr(n,d)
   z.writestr('_CAPSULE_INDEX.json',json.dumps({'content_id':'x','files':{n:{'sha256':resume.sha(d),'bytes':len(d)} for n,d in files.items()}}))
  raw=stream.getvalue()
  with self.assertRaises(ValueError):resume.restore(self.dest,raw,resume.sha(raw))
  self.assertFalse(self.dest.exists())
 def test_code_plan_needs_no_assets(self):
  (self.source/'recovery/assets.json').write_text(json.dumps({'files':[{'path':'missing.png','group':'runtime','bytes':4,'sha256':'x'}]}))
  self.assertEqual(resume.asset_plan(self.source,'code')['download_bytes'],0)
  self.assertEqual(resume.asset_plan(self.source,'runtime')['download_bytes'],4)
 def test_retirement_preserves_unknown_edits(self):
  self.dest.mkdir();path=self.dest/'retired.txt';path.write_bytes(b'known')
  entries=[{'path':'retired.txt','gitsha':resume.gitsha(b'known')}]
  self.assertEqual(resume.retire(self.dest,entries)['retired'],['retired.txt'])
  path.write_bytes(b'user edit')
  self.assertEqual(resume.retire(self.dest,entries)['conflicts'],['retired.txt'])
  self.assertEqual(path.read_bytes(),b'user edit')
 def test_retirement_protects_license_and_traversal(self):
  for name in ['LICENSE','legal/upstream/any.txt','../outside']:
   with self.subTest(name=name),self.assertRaises(ValueError):resume.retire(self.dest,[{'path':name,'gitsha':'x'}])
 def test_transient_asset_download_not_checkpointed(self):
  (self.source/'tmp-unfinished').write_text('partial temporary asset')
  self.assertNotIn('tmp-unfinished',resume.source_entries(self.source))
if __name__=='__main__':unittest.main(verbosity=2)
