#!/usr/bin/env python3
"""Author-time Rust execution. The deployed site only replays the resulting data.

Run the bundled planner first (see docs/algorithm-visualizations.md). No server
endpoint executes this script or accepts code for it. Only checked-in fixtures.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

PREFIX = '__CRABRIX_ATLAS__'


def normalize(expression):
    # Ignore formatting outside literals, preserving spaces/commas inside Rust
    # strings and chars. rustfmt adds optional trailing commas to calls/arrays.
    tokens = []; i = 0
    while i < len(expression):
        if expression[i].isspace(): i += 1; continue
        if expression[i] == '"':
            start = i; i += 1
            while i < len(expression):
                c = expression[i]; i += 1
                if c == '\\': i += 1
                elif c == '"': break
            tokens.append(expression[start:i]); continue
        char = re.match(r"'(?:\\.|[^'\\])'", expression[i:])
        if char: tokens.append(char[0]); i += len(char[0]); continue
        tokens.append(expression[i]); i += 1
    return ''.join(t for i, t in enumerate(tokens) if not (t == ',' and i + 1 < len(tokens) and tokens[i + 1] in [']', ')', '}']))


def rust_value(raw):
    """Parse Rust's standard Debug notation, preserving integers as exact text."""
    pos = 0

    def space():
        nonlocal pos
        while pos < len(raw) and raw[pos].isspace(): pos += 1

    def read():
        nonlocal pos
        space()
        start = pos
        if pos >= len(raw): raise ValueError('missing value')
        if raw[pos] in '\"\'':
            quote = raw[pos]; pos += 1
            while pos < len(raw):
                c = raw[pos]; pos += 1
                if c == '\\': pos += 1
                elif c == quote: break
            return {'kind': 'scalar', 'text': raw[start:pos]}
        pairs = {'[': ']', '(': ')', '{': '}'}
        if raw[pos] in pairs:
            opening = raw[pos]; closing = pairs[opening]; pos += 1
            items = []; entries = []
            space()
            while pos < len(raw) and raw[pos] != closing:
                key = read(); space()
                if pos < len(raw) and raw[pos] == ':':
                    pos += 1; entries.append([key, read()])
                else: items.append(key)
                space()
                if pos < len(raw) and raw[pos] == ',': pos += 1; space()
                elif pos >= len(raw) or raw[pos] != closing: raise ValueError('separator')
            if pos >= len(raw): raise ValueError('unterminated')
            pos += 1
            if entries:
                return {'kind': 'map', 'entries': sorted(entries, key=lambda e: json.dumps(e[0], sort_keys=True))}
            if opening == '{':
                return {'kind': 'set', 'items': sorted(items, key=lambda e: json.dumps(e, sort_keys=True))}
            return {'kind': 'list', 'items': items, 'tuple': opening == '('}
        while pos < len(raw) and raw[pos] not in '[](){},:' and not raw[pos].isspace(): pos += 1
        if pos == start: raise ValueError('atom')
        atom = raw[start:pos]; space()
        if pos < len(raw) and raw[pos] in '({':
            value = read()
            return {'kind': 'named', 'name': atom, 'value': value}
        return {'kind': 'scalar', 'text': atom}

    try:
        result = read(); space()
        if pos != len(raw): raise ValueError('trailing notation')
        return result
    except (ValueError, RecursionError):
        return {'kind': 'scalar', 'text': raw}


def repair(compiler_output, source):
    lines = source.splitlines(keepends=True)
    remove = set()

    def diagnostic(d):
        if d.get('level') == 'error':
            for s in d.get('spans', []):
                if s.get('file_name', '').endswith('traced.rs'):
                    for line in range(s['line_start'] - 1, min(s['line_end'], len(lines))):
                        if re.search(r'/\*__ATLAS_(?:CAPTURE|DERIVE)_\d+__\*/', lines[line]): remove.add(line)
        for child in d.get('children', []): diagnostic({**child, 'level': 'error'})

    for line in compiler_output.splitlines():
        try: diagnostic(json.loads(line))
        except json.JSONDecodeError: pass
    if not remove: return None
    return ''.join('\n' if i in remove else line for i, line in enumerate(lines))


def generate(path, work, output, fixtures):
    plan = json.loads(path.read_text()); key = plan['key']
    folder = work / key; folder.mkdir(parents=True, exist_ok=True)
    original = folder / 'original.rs'; original.write_text(plan['source'])
    def compile(file, binary):
        return subprocess.run(['rustc', '--edition=2024', '-Awarnings', '--error-format=json', str(file), '-o', str(binary)], capture_output=True, text=True, timeout=90)
    baseline = folder / 'original'
    result = compile(original, baseline)
    if result.returncode: raise RuntimeError(f'{key}: original compile failed: {result.stderr[:1000]}')
    result = subprocess.run([str(baseline)], capture_output=True, text=True, timeout=10)
    if result.returncode: raise RuntimeError(f'{key}: original run failed')
    stdout = result.stdout
    verified = key == 'demo-linear-scan' and stdout == '3\n'
    input_label = '[6, 2, 8, -1, 4]' if verified else ''
    normalized = normalize(plan['source'])
    for expression, text, expected in fixtures.get(plan['pattern'], []):
        if f'letresult={expression};' in normalized:
            if stdout.strip() != expected: raise RuntimeError(f'{key}: independent oracle mismatch {stdout!r} != {expected!r}')
            verified = True; input_label = text; break
    transformed = plan['transformed']; attempts = 0
    traced = folder / 'traced.rs'; binary = folder / 'traced'
    for attempts in range(40):
        traced.write_text(transformed)
        result = compile(traced, binary)
        if result.returncode == 0: break
        (folder / 'compile-errors.jsonl').write_text(result.stderr)
        repaired = repair(result.stderr, transformed)
        if repaired is None: raise RuntimeError(f'{key}: cannot safely repair captures: {result.stderr[:1800]}')
        transformed = repaired
    else: raise RuntimeError(f'{key}: capture repair limit')
    result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=15)
    if result.returncode or result.stdout != stdout:
        raise RuntimeError(f'{key}: instrumented behavior differs: {result.stderr[-1000:]}')
    raw_frames = [json.loads(line[len(PREFIX):]) for line in result.stderr.splitlines() if line.startswith(PREFIX)]
    if len(raw_frames) < 2: raise RuntimeError(f'{key}: missing execution steps')
    values = []; pool = {}; frames = []
    for frame in raw_frames:
        locals_ = []
        for name, raw, type_ in frame['locals']:
            value = rust_value(raw)
            if value['kind'] == 'set' and not value['items'] and re.search(r'HashMap|BTreeMap', type_):
                value = {'kind': 'map', 'entries': []}
            signature = json.dumps([type_, value], sort_keys=True)
            if signature not in pool:
                pool[signature] = len(values); values.append({'type': type_, 'data': value})
            locals_.append([name, pool[signature]])
        frames.append({'site': frame['site'], 'stack': frame['stack'], 'locals': locals_})
    captures = len(re.findall(r'/\*__ATLAS_CAPTURE_\d+__\*/', transformed))
    skipped = len(plan['captures']) - captures
    trace = {k: plan[k] for k in ['key', 'sourceHash', 'pattern', 'category', 'title', 'idea', 'complexity', 'source', 'sites']}
    trace.update(version=1, input=input_label, stdout=stdout, values=values, frames=frames,
                 verification={'stdoutMatchesOriginal': True, 'independentOracle': verified, 'omittedCaptures': skipped})
    encoded = json.dumps(trace, separators=(',', ':'), ensure_ascii=False) + '\n'
    if len(encoded.encode()) > 2 * 1024 * 1024: raise RuntimeError(f'{key}: exceeds bounded lesson payload')
    (output / f'{key}.json').write_text(encoded)
    # Executables are reproducible artifacts, keep the generated sources/logs only.
    baseline.unlink(); binary.unlink()
    return {'key': key, 'steps': len(frames), 'bytes': len(encoded.encode()), 'oracle': verified, 'omittedCaptures': skipped, 'compileRepairs': attempts}


def main():
    args = argparse.ArgumentParser()
    args.add_argument('--plans', type=Path, default=Path('../build/algorithm-atlas/plans'))
    args.add_argument('--output', type=Path, default=Path('content/algorithm-traces'))
    args.add_argument('--work', type=Path, default=Path('../build/algorithm-atlas/rust'))
    args.add_argument('--editorial-root', type=Path)
    args.add_argument('--only', default='')
    opts = args.parse_args()
    opts.output.mkdir(parents=True, exist_ok=True); opts.work.mkdir(parents=True, exist_ok=True)
    fixtures = {}
    if opts.editorial_root:
        sys.path.insert(0, str(opts.editorial_root.resolve()))
        from fixtures import call
        for f in json.loads((opts.editorial_root / 'example-verification.json').read_text())['fixtures']:
            try: expression = normalize(call(f['pattern'], f['input']))
            except Exception: continue
            fixtures.setdefault(f['pattern'], []).append((expression, f['input'], f['expected']))
    manifest = json.loads((opts.plans / 'manifest.json').read_text())
    keys = [k for k in manifest['keys'] if not opts.only or k.split('-')[0] in opts.only.split(',') or any(k.startswith(x) for x in opts.only.split(','))]
    records = []; errors = []
    with ThreadPoolExecutor(max_workers=4) as executor:
        futures = {executor.submit(generate, opts.plans / f'{key}.json', opts.work, opts.output, fixtures): key for key in keys}
        for future in as_completed(futures):
            try:
                record = future.result(); records.append(record)
                print(f'{len(records):3}/{len(keys)} {record["key"]}: {record["steps"]} steps, {record["compileRepairs"]} repairs', flush=True)
            except Exception as e: errors.append(str(e)); print(f'ERROR {e}', flush=True)
    report = {'compiler': subprocess.check_output(['rustc', '--version'], text=True).strip(), 'records': sorted(records, key=lambda r: r['key']), 'errors': errors}
    (opts.work.parent / 'verification.json').write_text(json.dumps(report, indent=2) + '\n')
    if errors: sys.exit(1)
    if not opts.only:
        if any(not r['oracle'] for r in records): raise RuntimeError('A fixture has no independent oracle. Supply --editorial-root.')
        manifest['keys'] = sorted(manifest['keys'])
        (opts.output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        current = set(manifest['keys']) | {'manifest'}
        for path in opts.output.glob('*.json'):
            if path.stem not in current: path.unlink()
    print(f'Verified {len(records)} examples; {sum(r["bytes"] for r in records):,} bytes.')


if __name__ == '__main__': main()
