from pathlib import Path
import subprocess,json,hashlib,sys
ROOT=Path(__file__).resolve().parents[3]
POSTS=ROOT/'site/content/posts.json';posts=json.loads(POSTS.read_text());new=posts[:6]
work=ROOT/'build/blog-backfill-20261104/examples';work.mkdir(parents=True,exist_ok=True)
fixtures=Path(__file__).parent/'examples';fixtures.mkdir(exist_ok=True)
rustc=Path('/Users/serhiirihgt/.cargo/bin/rustc');rustfmt=rustc.with_name('rustfmt')
rows=[]
for p in new:
 for index,s in enumerate(p['sections']):
  code=s.get('code');lang=s.get('codeLanguage','rust')
  if not code or lang!='rust':continue
  name=p['slug']+f'-{index}';src=work/(name+'.rs');src.write_text(code)
  subprocess.run([str(rustfmt),'--edition','2024',str(src)],check=True,capture_output=True,timeout=30)
  s['code']=src.read_text();(fixtures/src.name).write_text(s['code'])
  binary=work/name
  if p['slug']=='rust-1-99-1-patch-regression-testing':
   lib=work/'libeven.a';c=work/'caller.c';cs=next(x['code'] for x in p['sections'] if x.get('codeLanguage')=='c');c.write_text(cs);(fixtures/'caller.c').write_text(cs)
   subprocess.run([str(rustc),'--edition=2024','--crate-type','staticlib','-C','opt-level=2',str(src),'-o',str(lib)],check=True,capture_output=True,timeout=60)
   subprocess.run(['/usr/bin/cc','-std=c11','-O2',str(c),str(lib),'-o',str(binary)],check=True,capture_output=True,timeout=60)
   kind='macOS C/Rust static-library ABI smoke; no x86_64 regression reproduction claimed'
  else:
   subprocess.run([str(rustc),'--edition=2024',str(src),'-o',str(binary)],check=True,capture_output=True,timeout=60);kind='desktop Rust assertions'
  r=subprocess.run([str(binary)],check=True,capture_output=True,text=True,timeout=15)
  rows.append({'slug':p['slug'],'section':s['heading'],'kind':kind,'sourceSHA256':hashlib.sha256(src.read_bytes()).hexdigest(),'exit':r.returncode,'stdout':r.stdout,'stderr':r.stderr})
POSTS.write_text(json.dumps(posts,ensure_ascii=False,indent=2)+'\n')
receipt={'compiler':subprocess.check_output([str(rustc),'-Vv'],text=True),'date':'2026-11-04','programs':rows,'passed':len(rows),'scope':'Desktop fixture behavior only. Not a GPU backend, UEFI execution, x86_64 ABI regression or physical iPhone qualification.'}
(Path(__file__).parent/'example-verification.json').write_text(json.dumps(receipt,indent=2,ensure_ascii=False)+'\n');print(json.dumps(receipt,indent=2,ensure_ascii=False))
