"""Stage a fixed, original TypeScript compiler and libraries; no npm install hooks."""
import argparse, base64, hashlib, io, json, tarfile, zipfile
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--archive', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
archive = args.archive.read_bytes()
assert len(archive) == 4377468
assert base64.b64encode(hashlib.sha512(archive).digest()).decode() == 'jl1vZzPDinLr9eUt3J/t7V6FgNEw9QjvBPdysz9KfQDD41fQrC2Y4vKQdiaUpFT4bXlb1RHhLpp8wtm6M5TgSw=='
assert not args.output.exists(), 'Use a fresh candidate directory.'
root = Path(__file__).resolve().parent
with tarfile.open(args.archive, 'r:gz') as tar:
    def read(name):
        member = tar.getmember('package/' + name)
        assert member.isfile() and member.size <= 12 * 1024 * 1024
        return tar.extractfile(member).read()
    assert json.loads(read('package.json'))['version'] == '5.9.3'
    compiler = read('lib/typescript.js')
    library = {}
    for member in tar.getmembers():
        if member.name.startswith('package/lib/lib.') and member.name.endswith('.d.ts'):
            assert '/' not in member.name[len('package/lib/'):]
            name = member.name[len('package/'):]
            library['/' + name] = read(name).decode('utf-8')
    assert len(library) == 100  # Includes the legacy lib.d.ts entry, too.
    assets = {'compiler.js': compiler, 'library.json': json.dumps(library, ensure_ascii=False, separators=(',', ':')).encode(),
              'worker.js': (root/'worker.js').read_bytes(), 'host.js': (root/'host.js').read_bytes(),
              'index.html': (root/'index.html').read_bytes(), 'LICENSE.txt': read('LICENSE.txt'),
              'ThirdPartyNoticeText.txt': read('ThirdPartyNoticeText.txt')}
args.output.mkdir(parents=True)
notices = io.BytesIO()
with zipfile.ZipFile(notices, 'w', zipfile.ZIP_DEFLATED) as notice_archive:
    for name in ['LICENSE.txt', 'ThirdPartyNoticeText.txt']:
        entry = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0)); entry.compress_type = zipfile.ZIP_DEFLATED
        notice_archive.writestr(entry, assets[name])
assets['TypeScriptNotices.zip'] = notices.getvalue()
assets['TypeScriptNoticeIndex.json'] = (json.dumps([{'id':'typescript-5.9.3','name':'TypeScript 5.9.3',
    'summary':'Original Apache-2.0 compiler and standard declaration libraries; complete upstream third-party notices.',
    'archive':'TypeScriptNotices','documents':['LICENSE.txt','ThirdPartyNoticeText.txt']}],indent=2)+'\n').encode()
for name, data in assets.items(): (args.output/name).write_bytes(data)
runtime = {'index.html','host.js','worker.js','compiler.js','library.json'}
manifest = {'schemaVersion': 1, 'version': '5.9.3', 'candidateOnly': True,
    'archiveSHA256': hashlib.sha256(archive).hexdigest(), 'standardLibraries': len(library),
    'files': {name: {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()} for name,data in sorted(assets.items()) if name in runtime},
    'notices': {name: {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()} for name,data in sorted(assets.items()) if name not in runtime}}
(args.output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'version': manifest['version'], 'libraries': len(library), 'assetBytes':sum(map(len,assets.values())), 'candidateOnly':True}))
