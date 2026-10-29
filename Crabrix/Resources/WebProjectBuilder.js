/* Offline browser-project compiler. Only parses project text in this context.
 * Generated project code executes exclusively in the existing WebKit sandbox.
 * Babel plugins/configuration are fixed here; project plugins are never loaded.
 */
var CrabrixWebBuilder = (() => {
  const own = (o,k) => Object.prototype.hasOwnProperty.call(o,k);
  const cache = new Map();
  const prefix = 'crabrix-import:';
  const origin = 'crabrix-preview://project/';
  const extensions = ['', '.js', '.mjs', '.cjs', '.json', '.jsx', '.ts', '.tsx', '.mts', '.cts'];
  const builtins = new Set('assert async_hooks buffer child_process cluster console constants crypto dgram diagnostics_channel dns domain events fs http http2 https inspector module net os path perf_hooks process punycode querystring readline repl stream string_decoder sys timers tls trace_events tty url util v8 vm wasi worker_threads zlib'.split(' '));
  function failure(message,file='',line=1,column=1) { throw {webFailure:true,message,file,line,column}; }
  function normalize(path) {
    if (/[\\%\x00-\x1f\x7f]/.test(path)) failure('Unsupported or unsafe module path: '+path);
    const parts=[];
    for(const p of path.split('/')) {
      if(!p || p==='.') continue;
      if(p==='..') { if(!parts.length) failure('Module path escapes the project: '+path);parts.pop(); }
      else parts.push(p);
    }
    return parts.join('/');
  }
  const directory = p => p.includes('/') ? p.slice(0,p.lastIndexOf('/')) : '';
  const join = (a,b) => normalize(a ? a+'/'+b : b);
  const json = (text,path) => {try{return JSON.parse(text)}catch(_){failure('Invalid JSON in '+path,path)}};
  function literal(node) {
    if (!node) return {known:false};
    if(['StringLiteral','BooleanLiteral','NumericLiteral','NullLiteral'].includes(node.type)) return {known:true,value:node.type==='NullLiteral'?null:node.value};
    if(node.type==='UnaryExpression'&&node.operator==='!'){const x=literal(node.argument);if(x.known)return {known:true,value:!x.value};}
    if(node.type==='BinaryExpression') {
      const a=literal(node.left),b=literal(node.right);if(a.known&&b.known) {
        if(node.operator==='===')return {known:true,value:a.value===b.value};
        if(node.operator==='!==')return {known:true,value:a.value!==b.value};
      }
    }
    return {known:false};
  }
  function transform(source,file,jsxSource) {
    const key=file+'\0'+jsxSource+'\0'+source;
    if(cache.has(key))return cache.get(key);
    const t=Babel.packages.types, assets=[];
    const meta=node=>node&&node.type==='MetaProperty'&&node.meta.name==='import'&&node.property.name==='meta';
    const plugin=()=>({visitor:{
      ImportDeclaration(p){p.node.source.value=p.node.source.value.startsWith(prefix)?p.node.source.value:prefix+p.node.source.value},
      ExportNamedDeclaration(p){if(p.node.source)p.node.source.value=p.node.source.value.startsWith(prefix)?p.node.source.value:prefix+p.node.source.value},
      ExportAllDeclaration(p){p.node.source.value=p.node.source.value.startsWith(prefix)?p.node.source.value:prefix+p.node.source.value},
      ImportExpression(p){if(p.node.source.type!=='StringLiteral')failure('Dynamic imports need a literal module name.',file,p.node.loc?.start.line);p.node.source.value=p.node.source.value.startsWith(prefix)?p.node.source.value:prefix+p.node.source.value},
      AwaitExpression(p){if(!p.getFunctionParent())failure('Top-level await is not supported by the offline browser bundler. Move it into an async function.',file,p.node.loc?.start.line)},
      NewExpression(p){
        const a=p.node.arguments;
        if(p.node.callee.type==='Identifier'&&p.node.callee.name==='URL'&&a[0]?.type==='StringLiteral'&&a[1]?.type==='MemberExpression'&&meta(a[1].object)&&a[1].property.name==='url')assets.push(a[0].value);
      },
      MemberExpression:{enter(p){
        if(meta(p.node.object)&&['glob','globEager'].includes(p.node.property.name))failure('import.meta.glob needs a build-tool plugin. Use explicit local imports in Crabrix.',file,p.node.loc?.start.line);
      },exit(p){
        const n=p.node;
        if(n.object.type==='MemberExpression'&&n.object.object.type==='Identifier'&&n.object.object.name==='process'&&!p.scope.hasBinding('process')&&n.object.property.name==='env'&&n.property.name==='NODE_ENV')p.replaceWith(t.stringLiteral('production'));
      }},
      MetaProperty(p){if(meta(p.node))p.replaceWith(t.valueToNode({url:origin+file,env:{MODE:'production',DEV:false,PROD:true,BASE_URL:'/'}}))},
      IfStatement:{exit(p){const x=literal(p.node.test);if(x.known){const selected=x.value?p.node.consequent:p.node.alternate;if(selected)p.replaceWith(selected);else p.remove()}}},
      ConditionalExpression:{exit(p){const x=literal(p.node.test);if(x.known)p.replaceWith(x.value?p.node.consequent:p.node.alternate)}},
      LogicalExpression:{exit(p){const x=literal(p.node.left);if(x.known&&['&&','||','??'].includes(p.node.operator)){const right=p.node.operator==='&&'?!!x.value:p.node.operator==='||'?!x.value:x.value===null;if(right)p.replaceWith(p.node.right);else p.replaceWith(p.node.left)}}}
    }});
    let result;
    try {
      const presets=[['react',{runtime:'automatic',importSource:jsxSource}]];
      if(/\.(?:ts|tsx|mts|cts)$/.test(file))presets.unshift(['typescript',{onlyRemoveTypeImports:true}]);
      result=Babel.transform(source,{filename:file,sourceType:'unambiguous',presets,
        plugins:[plugin,'transform-export-namespace-from','transform-dynamic-import','transform-modules-commonjs'],ast:true,code:true,sourceMaps:false,comments:false,compact:false});
    } catch(error) {
      if(error.webFailure)throw error;
      failure(error.message||String(error),file,error.loc?.line||1,(error.loc?.column||0)+1);
    }
    const dependencies=[];
    Babel.packages.traverse.default(result.ast,{CallExpression(p){
      if(p.node.callee.type!=='Identifier'||p.node.callee.name!=='require'||p.scope.hasBinding('require'))return;
      const a=p.node.arguments;if(a.length!==1||a[0].type!=='StringLiteral')failure('require() needs a literal browser module name.',file,p.node.loc?.start.line);
      if(!dependencies.includes(a[0].value))dependencies.push(a[0].value);
    }});
    const compiled={code:result.code,dependencies,assets};
    if(cache.size>=256)cache.clear();cache.set(key,compiled);return compiled;
  }
  function build(input,preferredEntry,prepareTypes=false) {
    try {
      const files=Object.assign(Object.create(null),JSON.parse(input));
      const has=p=>own(files,p), used=new Set(), assets=Object.create(null), modules=Object.create(null), packageDependencies=new Map();
      const entry=preferredEntry&&has(preferredEntry)&&/\.html?$/.test(preferredEntry)?preferredEntry:
        has('index.html')?'index.html':Object.keys(files).filter(p=>/\.html?$/.test(p)&&!p.includes('node_modules/')).sort((a,b)=>a.split('/').length-b.split('/').length||a.localeCompare(b))[0];
      if(!entry)failure('A browser application needs an HTML entry. Add index.html or import a static export. Node server entry points cannot run in Web Preview.','package.json');
      function owner(file) {
        let d=directory(file);
        while(true){if(has(join(d,'package.json')))return d;if(!d)return '';d=directory(d)}
      }
      const root=owner(entry), rootPath=join(root,'package.json');
      const rootManifest=has(rootPath)?json(files[rootPath],rootPath):{};
      const jsxSource=rootManifest.crabrix?.jsxImportSource||'react';
      const locks=[];
      for(const name of ['crabrix-web.lock.json','package-lock.json']){
        const path=join(root,name);if(has(path)){const lock=json(files[path],path);if(name!=='crabrix-web.lock.json'||lock.manifest===files[rootPath])locks.push(name==='crabrix-web.lock.json'&&root?Object.fromEntries(Object.entries(lock.packages||{}).map(([p,v])=>[p.startsWith(root+'/')?p.slice(root.length+1):p,v])):lock.packages||{})}
      }
      const metadata=new Map();
      function manifest(d){const p=join(d,'package.json');if(!has(p))return {};if(!metadata.has(p))metadata.set(p,json(files[p],p));used.add(p);return metadata.get(p)}
      function sourceFile(path) {
        for(const ext of extensions)if(has(path+ext))return path+ext;
        for(const ext of extensions.slice(1))if(has(join(path,'index'+ext)))return join(path,'index'+ext);
        return null;
      }
      function exportTarget(value,mode,capture='') {
        if(value===null)return null;
        if(typeof value==='string')return value.replace(/\*/g,capture);
        if(Array.isArray(value)){for(const v of value){const found=exportTarget(v,mode,capture);if(found)return found}return null}
        if(value&&typeof value==='object')for(const [condition,v]of Object.entries(value))if(['browser','production',mode,'default'].includes(condition)){const found=exportTarget(v,mode,capture);if(found!==undefined)return found}
        return undefined;
      }
      function packageEntry(d,subpath,mode) {
        const m=manifest(d);let target;
        if(own(m,'exports')) {
          const key=subpath?'./'+subpath:'.', exports=m.exports;
          if(exports&&typeof exports==='object'&&!Array.isArray(exports)&&Object.keys(exports).some(k=>k.startsWith('.'))){
            if(own(exports,key))target=exportTarget(exports[key],mode);
            else {
              const patterns=Object.keys(exports).filter(k=>k.includes('*')).sort((a,b)=>b.indexOf('*')-a.indexOf('*')||b.length-a.length);
              for(const p of patterns){const [a,b]=p.split('*');if(key.startsWith(a)&&key.endsWith(b)){target=exportTarget(exports[p],mode,key.slice(a.length,key.length-b.length));break}}
            }
          } else if(key==='.')target=exportTarget(exports,mode);
          if(typeof target!=='string'||!target.startsWith('./')||normalize(target).startsWith('../'))failure('Package export is unavailable for browsers: '+(m.name||d)+(subpath?'/'+subpath:''),join(d,'package.json'));
        } else target=subpath||(typeof m.browser==='string'?m.browser:mode==='import'&&m.module?m.module:m.main||'index.js');
        const resolved=join(d,target);if(!resolved.startsWith(d+'/'))failure('Package entry escapes its source directory.',join(d,'package.json'));
        const found=sourceFile(resolved);if(!found)failure('Package source is incomplete: '+resolved+'. Prepare browser packages again.',join(d,'package.json'));
        return found;
      }
      function importMap(spec){
        const maps=files[entry].matchAll(/<script\b[^>]*type\s*=\s*["']importmap["'][^>]*>([\s\S]*?)<\/script\s*>/gi);
        for(const match of maps){const imports=json(match[1],entry).imports||{};if(own(imports,spec))return imports[spec]}
        return spec;
      }
      function resolve(raw,from) {
        let mode=raw.startsWith(prefix)?'import':'require', spec=raw.startsWith(prefix)?raw.slice(prefix.length):raw;
        spec=importMap(spec);
        if(typeof spec!=='string')failure('Invalid import-map target.',from);
        if(/^(?:https?:|data:|blob:|file:|node:|[A-Za-z]+:)/.test(spec))failure('External or server-only module '+spec+' is unavailable offline. Add a browser npm dependency or a local source file.',from);
        let projectAbsolute=false;
        const parent=owner(from), m=manifest(parent);
        const mapping=m.browser&&typeof m.browser==='object'?m.browser:{};
        const relative='./'+from.slice(parent?parent.length+1:0);
        if(own(mapping,spec)){
          if(mapping[spec]===false)return {empty:true,id:'empty:'+parent+':'+spec};spec=mapping[spec];
          if(typeof spec!=='string')failure('Invalid browser mapping.',join(parent,'package.json'));
          if(spec.startsWith('.')){spec='/'+join(parent,spec);projectAbsolute=true}
        }
        if(spec.startsWith('.')||spec.startsWith('/')){
          const query=spec.includes('?')?spec.slice(spec.indexOf('?')+1):'';if(query&&!['raw','url'].includes(query))failure('This asset import needs an unsupported build-tool plugin: '+spec,from);
          spec=spec.split('?')[0];let path=spec.startsWith('/')?(projectAbsolute?normalize(spec):join(root,normalize(spec))):join(directory(from),spec);
          const ownerRelative='./'+path.slice(parent?parent.length+1:0);
          if(own(mapping,ownerRelative)){
            if(mapping[ownerRelative]===false)return {empty:true,id:'empty:'+parent+':'+ownerRelative};path=join(parent,mapping[ownerRelative]);
          }
          let found=sourceFile(path);const relative=root&&path.startsWith(root+'/')?path.slice(root.length+1):path;if(!found&&has(join(root,'public/'+relative)))found=join(root,'public/'+relative);
          if(!found)failure('Local module or asset was not found: '+path,from);
          return {path:found,query,id:found+(query?'?'+query:'')};
        }
        if(builtins.has(spec)||builtins.has(spec.split('/')[0]))failure(spec+' requires Node APIs. Choose its browser export or a browser alternative.',from);
        return resolvePackage(spec,from,mode);
      }
      function resolvePackage(spec,from,mode,typesOnly=false) {
        const parent=owner(from), m=manifest(parent);
        const parts=spec.split('/'), name=spec.startsWith('@')?parts.slice(0,2).join('/'):parts[0], subpath=parts.slice(spec.startsWith('@')?2:1).join('/');
        if(!/^(?:@[a-z0-9][a-z0-9._-]*\/)?[a-z0-9][a-z0-9._-]*$/.test(name))failure('Unsupported npm package name: '+name,from);
        const declared=m.dependencies?.[name]||m.optionalDependencies?.[name]||m.peerDependencies?.[name]||(parent===root?m.devDependencies?.[name]:null);
        const candidates=[];let d=directory(from);
        while(true){if(!d.endsWith('node_modules'))candidates.push(join(d,'node_modules/'+name));if(!d)break;d=directory(d)}
        const satisfies=v=>!declared||CrabrixNpmSemver.satisfies(v,declared);
        for(const candidate of candidates)if(has(join(candidate,'package.json'))){const p=manifest(candidate);if(satisfies(p.version)){if(typesOnly)return {directory:candidate};const path=packageEntry(candidate,subpath,mode);return {path,id:path}}}
        if(typeof declared!=='string')failure('Declare '+name+' in '+join(parent,'package.json')+' before preparing browser packages.',from);
        if(!CrabrixNpmSemver.validRange(declared))failure('Only npm registry version ranges are supported: '+name+' '+declared,join(parent,'package.json'));
        let target=join(parent,'node_modules/'+name), ranges=[declared];
        const rootRange=rootManifest.dependencies?.[name]||rootManifest.devDependencies?.[name];
        const rootTarget=join(root,'node_modules/'+name);
        if(parent!==root&&rootRange&&CrabrixNpmSemver.intersects(declared,rootRange)&&!has(join(rootTarget,'package.json'))){target=rootTarget;ranges.push(rootRange)}
        let locked;
        for(const entries of locks){for(const candidate of candidates){const key=root?candidate.slice(root.length+1):candidate;const item=entries[key];if(item?.version&&satisfies(item.version)){target=candidate;locked=item;break}}if(locked)break}
        throw {missing:true,name,directory:target,requirements:ranges,importer:from,locked:locked||null};
      }
      function archiveRoot(file) {
        if(!file)return null;const parts=file.split('/'), index=parts.lastIndexOf('node_modules');
        return index<0?null:parts.slice(0,index+(parts[index+1].startsWith('@')?3:2)).join('/');
      }
      function visit(request,from) {
        const parent=archiveRoot(from), child=archiveRoot(request.path);
        if(parent&&child&&parent!==child){if(!packageDependencies.has(parent))packageDependencies.set(parent,new Set());packageDependencies.get(parent).add(child)}
        if(modules[request.id])return request.id;
        if(request.empty){modules[request.id]={code:'module.exports={};',dependencies:{}};return request.id}
        const file=request.path;used.add(file);manifest(owner(file));
        if(modules[request.id])return request.id;
        const row=modules[request.id]={code:'',dependencies:Object.create(null)};
        const ext=file.split('.').pop().toLowerCase();
        if(request.query==='raw'){row.code='module.exports='+JSON.stringify(files[file])+';';return request.id}
        if(request.query==='url'||['svg','txt','html','htm'].includes(ext)){
          assets[file]=files[file];row.code='module.exports='+JSON.stringify(origin+file)+';';return request.id;
        }
        if(ext==='json'){row.code='module.exports='+JSON.stringify(json(files[file],file))+';';return request.id}
        if(ext==='css'){
          if(file.endsWith('.module.css'))failure('CSS Modules need a separate transform. Use a regular CSS import in this browser build.',file);
          const css=files[file].replace(/@import\s+(?:url\(\s*)?[\"']([^\"']+)[\"']\s*\)?\s*([^;]*);/gi,(all,spec,conditions)=>{if(conditions.trim())failure('CSS @import conditions need a prebuilt stylesheet in this browser build.',file);const target=resolve(spec.startsWith('.')||spec.startsWith('/')?spec:'./'+spec,file);row.dependencies['css:'+spec]=visit(target,file);return ''}).replace(/url\(\s*(["']?)([^)'"\s]+)\1\s*\)/g,(all,q,url)=>{
            if(/^(?:data:|https?:|\/\/|#)/.test(url))return all;
            const p=url.startsWith('/')?join(root,normalize(url)):join(directory(file),url);if(has(p)){assets[p]=files[p];used.add(p);return 'url('+JSON.stringify(origin+p)+')'}return all;
          });
          row.code=Object.keys(row.dependencies).map(s=>'require('+JSON.stringify(s)+');').join('')+'const s=document.createElement("style");s.textContent='+JSON.stringify(css)+';document.head.appendChild(s);module.exports={};';return request.id;
        }
        if(!['js','mjs','cjs','jsx','ts','tsx'].includes(ext))failure('Unsupported browser asset: '+file,file);
        const out=transform(files[file],file,jsxSource);row.code=out.code;
        for(const dep of out.dependencies){const target=resolve(dep,file);row.dependencies[dep]=visit(target,file)}
        for(const ref of out.assets){const p=ref.startsWith('/')?join(root,normalize(ref)):join(directory(file),ref);if(!has(p))failure('Local URL asset was not found: '+p,file);assets[p]=files[p];used.add(p)}
        return request.id;
      }
      const comments=[...files[entry].matchAll(/<!--[\s\S]*?-->/g)].map(m=>[m.index,m.index+m[0].length]);
      let index=0;
      const output=files[entry].replace(/<script\b(?:[^>"']|"[^"]*"|'[^']*')*>[\s\S]*?<\/script\s*>/gi,(tag,offset)=>{
        if(comments.some(([a,b])=>offset>=a&&offset<b))return tag;
        const opening=tag.match(/^<script\b(?:[^>\"']|\"[^\"]*\"|'[^']*')*>/i)[0];
        const head=opening, attrs=Object.create(null);
        for(const a of head.matchAll(/([\w:-]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/g))attrs[a[1].toLowerCase()]=a[2]??a[3]??a[4]??'';
        const type=(attrs.type||'').toLowerCase(), src=attrs.src;
        if(type==='importmap')return tag;
        if(type!=='module'&&type!=='text/babel'&&type!=='text/jsx'&&!(src&&/\.(?:ts|tsx|jsx)(?:\?|$)/.test(src)))return tag;
        if(index>0)failure('Use one module script entry and import other modules from it.',entry);
        const start=opening.length, body=tag.slice(start,tag.toLowerCase().lastIndexOf('</'));
        let file;
        if(src){if(/^(?:[a-z]+:|\/\/)/i.test(src))failure('External module scripts cannot run offline. Use local files and prepared browser packages.',entry);file=src.startsWith('/')?join(root,normalize(src)):join(directory(entry),src);if(!has(file))failure('HTML module entry was not found: '+file,entry)}
        else {file=join(directory(entry),'__crabrix_inline_'+index+'.jsx');files[file]=body}
        const id=visit({id:file,path:file});const bundlePath='crabrix-web/entry-'+(index++)+'.js';
        const factories=Object.entries(modules).map(([name,row])=>JSON.stringify(name)+':[function(module,exports,require){\n'+row.code+'\n},'+JSON.stringify(row.dependencies)+']').join(',\n');
        assets[bundlePath]='(()=>{"use strict";const modules={'+factories+'},cache=Object.create(null);function load(id){if(Object.prototype.hasOwnProperty.call(cache,id))return cache[id].exports;const pair=modules[id];if(!pair)throw Error("Missing browser module "+id);const m=cache[id]={exports:{}};pair[0](m,m.exports,s=>{if(!Object.prototype.hasOwnProperty.call(pair[1],s))throw Error("Unprepared module "+s);return load(pair[1][s])});return m.exports}load('+JSON.stringify(id)+')})();';
        return '<script src="/'+bundlePath+'" defer></script>';
      });
      for(const [path,text]of Object.entries(files))if(!path.endsWith('crabrix-web.lock.json')&&!path.includes('node_modules/')&&!/\.(?:ts|tsx|mts|cts|jsx)$/.test(path)&&!path.includes('__crabrix_inline_')){
        assets[path]=text;const local=root&&path.startsWith(root+'/')?path.slice(root.length+1):path;if(root&&path.startsWith(root+'/'))assets[local]=text;if(local.startsWith('public/'))assets[local.slice(7)]=text;
      }
      assets[entry]=output;
      let packageRoots=[...metadata.keys()].filter(p=>{
        const parts=directory(p).split('/'), index=parts.lastIndexOf('node_modules');
        return index>=0 && parts.length-index-1===(parts[index+1].startsWith('@')?2:1);
      });
      if(prepareTypes){
        const queued=packageRoots.map(path=>({directory:directory(path),required:false})), retained=new Set();
        for(const name of new Set([...Object.keys(rootManifest.dependencies||{}),...Object.keys(rootManifest.devDependencies||{})].filter(name=>name.startsWith('@types/')))){
          queued.push({...resolvePackage(name,rootPath,'types',true),required:true});
        }
        for(let index=0;index<queued.length;index++){
          if(index>=2048)failure('The declaration dependency graph exceeds 2,048 packages.',rootPath);
          const item=queued[index], dir=item.directory;
          if(retained.has(dir))continue;
          const declarations=Object.keys(files).filter(path=>path.startsWith(dir+'/')&&!path.slice(dir.length+1).includes('node_modules/')&&/\.d\.(?:ts|mts|cts)$/.test(path));
          if(!declarations.length&&!item.required)continue;
          retained.add(dir);manifest(dir);for(const path of declarations)used.add(path);
          for(const name of Object.keys(manifest(dir).dependencies||{})){
            const child=resolvePackage(name,join(dir,'package.json'),'types',true).directory;
            if(!packageDependencies.has(dir))packageDependencies.set(dir,new Set());packageDependencies.get(dir).add(child);
            queued.push({directory:child,required:true});
          }
        }
        packageRoots=[...new Set([...packageRoots,...[...retained].map(dir=>join(dir,'package.json'))])];
      }
      for(const p of packageRoots){const dir=directory(p);for(const f of Object.keys(files)){
        if(!f.startsWith(dir+'/'))continue;
        const relative=f.slice(dir.length+1);
        if(/^(?:licen[cs]e[s]?|copying|notice)(?:[._-][^/]*|\/.*)?$/i.test(relative)||/^readme(?:\.md|\.txt)?$/i.test(relative))used.add(f);
      }}
      return JSON.stringify({entry,manifestPath:rootPath,assets,usedPaths:[...used].filter(p=>!p.includes('__crabrix_inline_')),packageRoots:packageRoots.map(directory),packageDependencies:Object.fromEntries([...packageDependencies].map(([p,children])=>[p,[...children].sort()])),moduleCount:Object.keys(modules).length});
    }catch(error){
      if(error.missing)return JSON.stringify({missing:error});
      return JSON.stringify({error:{message:error.message||String(error),file:error.file||'',line:error.line||1,column:error.column||1}});
    }
  }
  return {build,selectVersion:(versions,ranges)=>versions.filter(v=>ranges.every(r=>CrabrixNpmSemver.satisfies(v,r))).sort(CrabrixNpmSemver.rcompare)[0]||null};
})();
