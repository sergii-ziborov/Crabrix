from pathlib import Path
import tarfile,hashlib,base64,json
import argparse
parser=argparse.ArgumentParser(description='Vendor pinned highlight.js grammars from a verified npm archive; no network access.')
parser.add_argument('--archive',type=Path,required=True)
a=parser.parse_args().archive
r=Path(__file__).resolve().parents[1]
w=a.parent
assert base64.b64encode(hashlib.sha512(a.read_bytes()).digest()).decode()=='nbfWpyRMcMrPMmDwJB+dhX/eiaPKtc2RB+0QZskqJ3WjRA/FDS0e9hZrx8EC/lbEv8gXy98FcDbNa/dspAaJMg=='
with tarfile.open(a) as t:
 def read(p):return t.extractfile('package/'+p).read().decode()
 code='// highlight.js 11.12.0, BSD-3-Clause. Bundled offline grammar, not user code.\nvar crabrixHighlighter = (() => {\nconst module = {exports:{}};\n'+read('lib/core.js')+'\nconst hljs = module.exports;\n'
 for lang in ['xml','css','javascript','typescript','json','markdown','yaml']:
  code+='\n{const module = {exports:{}};\n'+read('lib/languages/'+lang+'.js')+'\nhljs.registerLanguage('+json.dumps(lang)+', module.exports);}\n'
 code+='''
const kind = scope => {
 const s = (scope || '').split('.')[0];
 if (['comment','quote','meta'].includes(s)) return 'comment';
 if (['string','regexp','char','doctag'].includes(s)) return 'string';
 if (['number','literal'].includes(s)) return 'number';
 if (['keyword','selector-tag','tag'].includes(s)) return 'keyword';
 if (['type','built_in','title','section'].includes(s)) return 'type';
 if (['attr','attribute','property','selector-class','selector-id','bullet'].includes(s)) return 'key';
 return null;
};
return (source, language) => {
 const tokens=[]; let offset=0;
 const walk=(node, inherited=null) => {
   if (typeof node==='string') {
     if(inherited && node.length) tokens.push({kind:inherited,start:offset,length:node.length});
     offset+=node.length; return;
   }
   const scope=kind(node.scope) || inherited;
   for(const child of node.children || []) walk(child, scope);
 };
 const result=hljs.highlight(source,{language,ignoreIllegals:true});
 walk(result._emitter.rootNode);
 return tokens;
};
})();
'''
 (r/'Crabrix/Resources/WebSyntax.js').write_text(code)
 (r/'Crabrix/Resources/Licenses/highlight.js-LICENSE.txt').write_text(read('LICENSE'))
 (w/'highlight-source-lock.json').write_text(json.dumps(dict(version='11.12.0',archiveSHA512=base64.b64encode(hashlib.sha512(a.read_bytes()).digest()).decode(),bundleSHA256=hashlib.sha256(code.encode()).hexdigest()),indent=2))
