/** Only Cargo directives that do not grant host capabilities are accepted. */
export function buildScriptDirectives(stdout: string): { args: string[]; env: string[] } {
    const args: string[] = [], env: string[] = [];
    for (const line of stdout.split(/\r?\n/)) {
        if (!line.startsWith('cargo:')) continue;
        const directive = line.replace(/^cargo::?/, ''), at = directive.indexOf('=');
        if (at < 1) throw new Error('Malformed Cargo build directive.');
        const key = directive.slice(0, at), value = directive.slice(at + 1);
        if (value.length > 4096 || /[\x00-\x1f\x7f]/.test(value)) throw new Error('Invalid Cargo build directive value.');
        if (key === 'rustc-cfg') {
            if (!/^[A-Za-z_][A-Za-z0-9_]*(?:\s*=\s*"[^"\\\x00-\x1f]*")?$/.test(value) || /^(?:target_|feature(?:\s|=|$)|panic(?:\s|=|$))/.test(value)) throw new Error('Unsupported Cargo build cfg.');
            args.push('--cfg', value);
        } else if (key === 'rustc-check-cfg') {
            if (!/^cfg\([A-Za-z0-9_(), "=.-]+\)$/.test(value)) throw new Error('Unsupported Cargo check-cfg.');
            args.push('--check-cfg', value);
        } else if (key === 'rustc-env') {
            const split = value.indexOf('='), name = value.slice(0, split);
            if (split < 1 || !/^[A-Za-z_][A-Za-z0-9_]*$/.test(name) || /^(?:CARGO_|RUST|CLIF|CRABRIX_|OUT_DIR$|HOST$|TARGET$|PWD$|TMPDIR$|PATH$)/.test(name)) throw new Error('Cargo build script cannot replace runner environment.');
            env.push(value);
        } else if (key === 'error') throw new Error('Cargo build script: ' + value);
        else if (!['warning', 'rerun-if-changed', 'rerun-if-env-changed'].includes(key)) throw new Error('Unsupported Cargo build directive: ' + key);
        if (args.length + env.length > 256) throw new Error('Too many Cargo build directives.');
    }
    return { args, env };
}
