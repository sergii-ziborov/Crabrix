"""Run complete article programs on desktop Rust; never an iPhone benchmark."""
import hashlib,json,os,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'build/blog-backfill-20261029/examples'
OUT.mkdir(parents=True,exist_ok=True)
posts=json.loads((ROOT/'site/content/posts.json').read_text())
slugs={'rust-serde-json-validation-boundaries','rust-arc-mutex-rwlock-shared-state'}
rows=[]
for post in posts:
 if post['slug'] not in slugs:continue
 serde='serde-json' in post['slug']
 crate=OUT/('serde-lab' if serde else 'shared-lab');(crate/'src/bin').mkdir(parents=True,exist_ok=True)
 for old in (crate/'src/bin').glob('*.rs'): old.unlink()
 manifest=next((s['code'] for s in post['sections'] if s.get('codeLanguage')=='toml'), '[package]\nname="shared-state-lab"\nversion="0.1.0"\nedition="2024"')
 (crate/'Cargo.toml').write_text(manifest+'\n')
 cases=[]
 for index,s in enumerate(post['sections']):
  if s.get('codeLanguage')!='rust':continue
  name=f'case_{index:02d}';p=crate/'src/bin'/f'{name}.rs';p.write_text(s['code']+'\n');cases.append((name,s))
 pinned=ROOT/'docs/blog/backfill-2026-10-29'/f'{crate.name}.Cargo.lock'
 if pinned.exists(): (crate/'Cargo.lock').write_bytes(pinned.read_bytes())
 # Build once per article, then give every program its own bounded run.
 env=dict(os.environ,CARGO_TARGET_DIR=str(OUT/'target'))
 built=subprocess.run(['cargo','build','--locked','--manifest-path',str(crate/'Cargo.toml'),'--bins'],env=env,capture_output=True,text=True,timeout=180)
 if built.returncode:raise RuntimeError(built.stderr)
 for name,s in cases:
  run=subprocess.run([str(OUT/'target/debug'/name)],capture_output=True,text=True,timeout=15)
  if run.returncode:raise RuntimeError(f'{post["slug"]}/{name}: {run.stderr}')
  rows.append({'slug':post['slug'],'heading':s['heading'],'codeSHA256':hashlib.sha256(s['code'].encode()).hexdigest(),'exitCode':run.returncode,'stdout':run.stdout,'stderr':run.stderr,'timeoutSeconds':15})
 lock=crate/'Cargo.lock'
 (ROOT/'docs/blog/backfill-2026-10-29'/f'{crate.name}.Cargo.lock').write_bytes(lock.read_bytes())
result={'platform':'desktop macOS','compiler':subprocess.check_output(['rustc','--version'],text=True).strip(),'physicalDeviceBenchmark':False,'backendExecution':False,'cases':rows}
(ROOT/'docs/blog/backfill-2026-10-29/example-verification.json').write_text(json.dumps(result,indent=2)+'\n')
print(f'{len(rows)} complete programs passed their assertions on desktop Rust.')
