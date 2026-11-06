import type {AlgorithmTrace, AtlasValue} from './algorithm-trace-types.ts';

/** Compare only snapshots from the same call, including after a nested call returns. */
export function previousFrameIndices(frames: AlgorithmTrace['frames']): (number|undefined)[] {
  const last=new Map<number,number>();
  return frames.map((frame,index)=>{
    const activation=frame.stack.at(-1)?.[1];
    if(activation===undefined)return undefined;
    const previous=last.get(activation);last.set(activation,index);return previous;
  });
}

/** Structural identity does not confuse display text with a differently typed key. */
export function atlasValueKey(value:AtlasValue):string {
  switch(value.kind){
    case 'scalar':return JSON.stringify(['scalar',value.text]);
    case 'list':return JSON.stringify(['list',!!value.tuple,value.items.map(atlasValueKey)]);
    case 'named':return JSON.stringify(['named',value.name,atlasValueKey(value.value)]);
    case 'set':return JSON.stringify(['set',value.items.map(atlasValueKey).sort()]);
    case 'map':return JSON.stringify(['map',value.entries.map(([k,v])=>[atlasValueKey(k),atlasValueKey(v)]).sort((a,b)=>a[0].localeCompare(b[0]))]);
  }
}

export function collectionChanges(value:AtlasValue,previous?:AtlasValue){
  const added=new Set<string>(),updated=new Set<string>();
  const removed:{key:AtlasValue;value?:AtlasValue}[]=[];
  if(value.kind==='map'&&previous?.kind==='map'){
    const before=new Map(previous.entries.map(([k,v])=>[atlasValueKey(k),{key:k,value:v}]));
    const current=new Set<string>();
    for(const [k,v] of value.entries){const key=atlasValueKey(k);current.add(key);const old=before.get(key);if(!old)added.add(key);else if(atlasValueKey(old.value)!==atlasValueKey(v))updated.add(key);}
    for(const [key,old] of before)if(!current.has(key))removed.push(old);
  }else if(value.kind==='set'&&previous?.kind==='set'){
    const before=new Map(previous.items.map(v=>[atlasValueKey(v),v]));
    const current=new Set(value.items.map(atlasValueKey));
    for(const key of current)if(!before.has(key))added.add(key);
    for(const [key,old] of before)if(!current.has(key))removed.push({key:old});
  }
  return {added,updated,removed};
}
