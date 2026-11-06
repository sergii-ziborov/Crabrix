import test from 'node:test';
import assert from 'node:assert/strict';
import {sourceIndexBindings} from '../lib/algorithm-index-bindings.ts';
test('labels belong to their collection and ignore parameters, comments and quoted examples',()=>{
  const source=String.raw`fn main(){
    let cost=0; let k=2; let answer=values[left]+values[right];
    let cell=dp[row][column];
    for (index, value) in items.iter().enumerate() { println!("{}",value); }
    // values[cost]
    /* dp[k] /* items[answer] */ values[k] */
    let caption=r#"values[cost]"#; let text="items[k]";
    other[column];
  }`;
  const bindings=sourceIndexBindings(source);
  assert.deepEqual([...bindings.get('values')],['left','right']);
  assert.deepEqual([...bindings.get('dp')],['row','column']);
  assert.deepEqual([...bindings.get('items')],['index']);
  assert.deepEqual([...bindings.get('other')],['column']);
  for(const names of bindings.values())assert(!names.has('cost')&&!names.has('k')&&!names.has('answer'));
});
test('nested indirect expressions and numeric literals do not invent a scalar pointer',()=>{
  const bindings=sourceIndexBindings('fn main(){ values[indices[i]]; values[0]; other[j]; }');
  assert.equal(bindings.has('values'),false);assert.deepEqual([...bindings.get('indices')],['i']);
  assert.deepEqual([...bindings.get('other')],['j']);
});
