import captured from './playground-target-cfg.json' with { type: 'json' };
import toolchain from './playground-toolchain.json' with { type: 'json' };
// Captured from the exact released WASM rustc, not the developer's host rustc.
if (captured.compilerSHA256 !== toolchain.compiler.expandedSHA256) throw new Error('Cargo target facts need qualification for this compiler.');
const values: Record<string, readonly string[]> = captured.values;
const flags = new Set(captured.flags);
export const cargoTargetEnvironment = Object.entries({ ...Object.fromEntries(captured.flags.map(key => [key, ''])), ...Object.fromEntries(Object.entries(values).map(([key, value]) => [key, value.join(',')])) })
    .map(([key, value]) => 'CARGO_CFG_' + key.toUpperCase() + '=' + value);

/** Parse Cargo's target predicates; never evaluate manifest text as JavaScript. */
export function cargoTargetMatches(target: string): boolean {
    if (target === 'wasm32-wasip1') return true;
    if (!target.startsWith('cfg(')) {
        if (!/^[a-z0-9_]+(?:-[a-z0-9_]+){1,4}$/.test(target)) throw new Error('Unsupported Cargo target selector.');
        return false;
    }
    if (target.length > 4096) throw new Error('Cargo target predicate is too large.');
    const tokens = target.match(/\s+|[A-Za-z_][A-Za-z0-9_]*|"(?:[^"\\]|\\["\\])*"|[(),=]/g) ?? [];
    if (tokens.join('') !== target) throw new Error('Unsupported Cargo target predicate syntax.');
    const input = tokens.filter(t => !/^\s+$/.test(t)); let at = 0;
    const take = (s: string) => { if (input[at++] !== s) throw new Error('Malformed Cargo target predicate.'); };
    function predicate(depth = 0): boolean {
        if (depth > 32) throw new Error('Cargo target predicate nesting limit.');
        const name = input[at++];
        if (!name || !/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) throw new Error('Malformed Cargo cfg name.');
        if (input[at] === '(') {
            if (!['all', 'any', 'not'].includes(name)) throw new Error('Unsupported Cargo cfg operator.');
            at++; const args: boolean[] = [];
            while (input[at] !== ')') {
                args.push(predicate(depth + 1));
                if (input[at] !== ',') break;
                at++;
            }
            take(')');
            if (name === 'not' && args.length !== 1) throw new Error('Cargo not() takes one predicate.');
            return name === 'all' ? args.every(Boolean) : name === 'any' ? args.some(Boolean) : !args[0];
        }
        if (input[at] === '=') {
            at++; const token = input[at++];
            if (!token?.startsWith('"')) throw new Error('Cargo cfg value must be a string.');
            // Cargo does not support dependency selection using feature cfgs.
            if (name === 'feature' || name.startsWith('target_') && !(name in values)) throw new Error('Unsupported Cargo cfg key.');
            return values[name]?.includes(JSON.parse(token)) ?? false;
        }
        if (name.startsWith('target_') && !flags.has(name) || name === 'feature') throw new Error('Unsupported Cargo cfg flag.');
        return name === 'true' || flags.has(name);
    }
    take('cfg'); take('('); const result = predicate(); take(')');
    if (at !== input.length) throw new Error('Trailing Cargo target predicate tokens.');
    return result;
}
