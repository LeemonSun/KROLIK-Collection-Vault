#!/usr/bin/env python3
"""Two independent app processes, one isolated synthetic user profile."""
import os,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='companion-restart-') as temporary:
 for stage in ['write','read']:
  env=dict(os.environ,XDG_DATA_HOME=temporary,XDG_CONFIG_HOME=temporary,COMPANION_PERSIST_STAGE=stage)
  result=subprocess.run([sys.argv[1],'--headless','--path',str(ROOT),'--script','res://tests/test_persistence.gd','--','--test-mode'],env=env,capture_output=True,text=True,timeout=15)
  output=result.stdout+result.stderr
  print(output)
  if result.returncode or 'SCRIPT ERROR:' in output or '\nERROR:' in output:raise SystemExit(1)
