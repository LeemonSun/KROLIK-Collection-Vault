#!/usr/bin/env python3
"""Independent DOCX/XLSX fixture producers and readback; development only."""
import os,sys,tempfile,subprocess,zipfile
from pathlib import Path
from docx import Document
from openpyxl import Workbook,load_workbook
ROOT=Path(__file__).resolve().parents[1]
def main():
 with tempfile.TemporaryDirectory(prefix='leemon-office-') as folder:
  base=Path(folder)
  doc=Document();p=doc.add_paragraph();p.add_run('Исходный текст 中文').bold=True
  p=doc.add_paragraph();p.add_run('split ').bold=True;p.add_run('across').italic=True
  doc.add_paragraph('repeat');doc.add_paragraph('repeat');doc.save(base/'sample.docx')
  book=Workbook();book.active.title='First';book.active['A1']='untouched'
  second=book.create_sheet('Данные');second['B2']='Старое 中文';second['B2'].number_format='@';second['C2']=42;second['D2']=True;second['E2']='number-looking';second['B3']=1.25;second['C3']=2.5;second['D3']='100'
  book.save(base/'sample.xlsx')
  formula=Workbook();formula.active['A1']=1;formula.active['B1']='=A1+1';formula.save(base/'formula.xlsx')
  for name,entry,data in [('bomb.zip','huge.xml',b'a'*3000000),('traversal.zip','../outside',b'x')]:
   with zipfile.ZipFile(base/name,'w',zipfile.ZIP_DEFLATED) as z:z.writestr(entry,data)
  originals={name:{n:z.read(n) for n in z.namelist()} for name in ['sample.docx','sample.xlsx'] for z in [zipfile.ZipFile(base/name)]}
  pack=os.environ.get('LEEMON_TEST_PACK')
  command=[sys.argv[1],'--headless','--path',str(Path(pack).parent if pack else ROOT)]
  if pack:command+=['--main-pack',pack]
  command+=['--script',str(ROOT/'tests/test_office.gd') if pack else 'res://tests/test_office.gd','--','--test-mode']
  result=subprocess.run(command,env=dict(os.environ,LEEMON_OFFICE_FIXTURE=folder,XDG_DATA_HOME=folder+'/profile',XDG_CONFIG_HOME=folder+'/profile'),capture_output=True,text=True,timeout=60)
  log=result.stdout+result.stderr;print(log)
  if result.returncode or 'SCRIPT ERROR:' in log or '\nERROR:' in log:return 1
  doc=Document(base/'sample.docx');assert doc.paragraphs[0].text==' Новый & текст <ok> ' and doc.paragraphs[0].runs[0].bold
  assert doc.paragraphs[1].text=='spЖ跨ss' and doc.paragraphs[1].runs[0].bold and doc.paragraphs[1].runs[1].italic
  book=load_workbook(base/'sample.xlsx');assert book['Данные']['B2'].value=='=literal text' and book['Данные']['B2'].data_type=='s'
  assert book['Данные']['C2'].value==12.5 and book['Данные']['C2'].data_type=='n' and book['Данные']['D2'].value is False and book['Данные']['E2'].value=='00042' and book['First']['A1'].value=='untouched' and book['Данные']['B2'].number_format=='@'
  for name,changed in [('sample.docx','word/document.xml'),('sample.xlsx','xl/worksheets/sheet2.xml')]:
   with zipfile.ZipFile(base/name) as z:
    assert {n for n in z.namelist() if not n.endswith('/')}=={n for n in originals[name] if not n.endswith('/')} and z.testzip() is None
    assert all(z.read(n)==data for n,data in originals[name].items() if n!=changed)
  print('INDEPENDENT_OFFICE_READBACK: PASS; python-docx, openpyxl, CRC, all untouched package parts byte-identical')
 return 0
if __name__=='__main__':raise SystemExit(main())
