import {parser} from '@lezer/rust';

/** Presentation hints from this collection's source, not arbitrary scalar values. */
export function sourceIndexBindings(source:string):Map<string,Set<string>>{
  const code=source.split('');
  parser.parse(source).iterate({enter(node){
    if(['String','RawString','ByteString','RawByteString','Char','ByteChar','LineComment','BlockComment'].includes(node.name)){
      for(let i=node.from;i<node.to;i++)code[i]=' ';
      return false;
    }
  }});
  const text=code.join(''),bindings=new Map<string,Set<string>>();
  const add=(name:string,index:string)=>{let values=bindings.get(name);if(!values){values=new Set();bindings.set(name,values);}values.add(index);};
  for(const match of text.matchAll(/\b([A-Za-z_][A-Za-z0-9_]*)\s*((?:\[\s*[A-Za-z_][A-Za-z0-9_]*\s*\])+)/g)){
    for(const index of match[2].matchAll(/\[\s*([A-Za-z_][A-Za-z0-9_]*)\s*\]/g))add(match[1],index[1]);
  }
  for(const match of text.matchAll(/\bfor\s*\(\s*(?:mut\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*,[^\n]*?\)\s+in\s+([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*(?:iter|iter_mut|into_iter)\s*\(\s*\)\s*\.\s*enumerate\s*\(/g))add(match[2],match[1]);
  return bindings;
}
