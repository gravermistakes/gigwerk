#!/usr/bin/env python3
"""Deterministic compiler/test driver. Never writes an exercise algorithm."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import re
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
from status import classify

BASE = Path(__file__).resolve().parents[1]


def read_json(path, default=None):
    return json.loads(path.read_text()) if path.exists() else ({} if default is None else default)


def top_arrows(text):
    depths = [0, 0, 0]
    arrows = 0
    for index, char in enumerate(text):
        if char in '({[':
            depths['({['.index(char)] += 1
        if char in ')}]':
            depths[')}]'.index(char)] -= 1
        if char == '-' and text[index:index + 2] == '->' and not any(depths):
            arrows += 1
    return arrows


def constructors(contract):
    rows = []
    family = None
    for line in contract.splitlines():
        found = re.match(r'^data\s+([A-Za-z_]\w*)\b.*\bwhere\s*$', line)
        if found:
            family = found.group(1)
            continue
        if family and line and not line[0].isspace():
            family = None
        found = re.match(r'^\s+([A-Z]\w*)\s*::\s*(.+)$', line)
        if family and found:
            name, signature = found.groups()
            arity = top_arrows(signature)
            representation = 'named:' + name
            if name in {'Nil', 'LNil', 'INil'} and arity == 0:
                representation = 'list_nil'
            elif name in {'Cons', 'LCons', 'ICons'} and arity == 2:
                representation = 'list_cons'
            elif name in {'Nothing', 'None', 'Absent'} and arity == 0:
                representation = 'named:None'
            elif name in {'Just', 'Some', 'Present'} and arity == 1:
                representation = 'named:Some'
            elif name in {'Pair', 'MkPair'} and arity == 2:
                representation = 'tuple'
            rows.append((name, arity, family, representation))
    return rows


def interface_parts(meta):
    signatures = {}
    entries = meta.get('entrypoints', meta.get('functions', []))
    if isinstance(entries, dict):
        entries = [dict(name=name, signature=value) if isinstance(value, str)
                   else dict(value, name=name) for name, value in entries.items()]
    if isinstance(entries, list):
        for item in entries:
            if isinstance(item, dict):
                name = item.get('name')
                signature = item.get('signature', item.get('ocaml_signature', item.get('type')))
                if isinstance(name, str) and isinstance(signature, str):
                    signatures[name] = signature.removeprefix('val ' + name + ' :').strip()
    extra = meta.get('signatures', {})
    if isinstance(extra, dict):
        signatures.update({k: v for k, v in extra.items() if isinstance(v, str)})
    declarations = []
    for key in ('types', 'type_declarations', 'ocaml_types', 'datatype_declarations'):
        values = meta.get(key, [])
        if isinstance(values, dict):
            values = list(values.values())
        if isinstance(values, str):
            values = [values]
        for value in values:
            if isinstance(value, dict):
                value = value.get('declaration', value.get('ocaml', value.get('definition', '')))
            if isinstance(value, str) and value.lstrip().startswith('type '):
                declarations.append(value.strip())
    for key in ('ocaml_interface', 'interface'):
        value = meta.get(key)
        if isinstance(value, str):
            for name, signature in re.findall(r'^val\s+(\w+)\s*:\s*(.+)$', value, re.M):
                signatures[name] = signature
    return list(dict.fromkeys(declarations)), signatures


def run(command, cwd, timeout=30):
    try:
        result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, timeout=timeout)
        return result.returncode, result.stdout + result.stderr
    except subprocess.TimeoutExpired as error:
        text = (error.stdout or b'') + (error.stderr or b'')
        if isinstance(text, bytes):
            text = text.decode(errors='replace')
        return 124, text + '\nexternal timeout\n'


def verify_item(directory, backend=None, assessment=None):
    directory = Path(directory)
    backend = Path(backend or BASE/'backend/synquid-ocaml')
    assessment = dict(assessment or read_json(directory/'assessment.json'))
    result = dict(id=directory.name, title=assessment.get('title', directory.name),
                  contract=assessment.get('contract_status', 'missing'),
                  strength=assessment.get('specification_strength', 'none'),
                  synthesis=assessment.get('synthesis_status', 'not_attempted'),
                  lowering=False, interface=False, compiled=False, tests=False,
                  test_exit=None, elapsed_seconds=0, notes=[])
    start = time.monotonic()
    if not directory.is_dir():
        result['status'] = 'missing'
        result['notes'].append('declared catalogue item has no artifact directory')
        return result
    if result['synthesis'] != 'candidate':
        result['status'] = classify(**{key: result[key] for key in
            ('contract', 'strength', 'synthesis', 'lowering', 'interface', 'compiled', 'tests', 'test_exit')})
        return result
    output = directory/'synthesis.out'
    if not output.exists():
        alternatives = sorted(directory.glob('*.out'))
        alternatives = [path for path in alternatives if 'negative' not in path.name and 'recheck' not in path.name]
        output = alternatives[0] if alternatives else output
    work = directory/'verification'
    work.mkdir(exist_ok=True)
    try:
        meta = read_json(directory/'interface.json')
        declarations, signatures = interface_parts(meta)
        result['interface'] = bool(signatures)
        rows = constructors((directory/'contract.sq').read_text() if (directory/'contract.sq').exists() else '')
        (work/'constructors.tsv').write_text(''.join('\t'.join(map(str, row))+'\n' for row in rows))
        (work/'primitives.txt').write_text('')
        code, log = run([str(backend), str(output), str(work/'constructors.tsv'), str(work/'primitives.txt')], work)
        (work/'lowering.log').write_text(log)
        if code != 0:
            result['notes'].append('lowering refused; see verification/lowering.log')
        else:
            result['lowering'] = True
            (work/'generated.ml').write_text('\n'.join(declarations)+'\n'+log)
            if signatures:
                (work/'generated.mli').write_text('\n'.join(declarations)+'\n'+
                    '\n'.join('val '+name+' : '+signature for name, signature in signatures.items())+'\n')
                code, compile_log = run(['ocamlc','-c','generated.mli'], work)
            else:
                code, compile_log = 0, ''
            test = directory/'test_generated.ml'
            if not test.exists():
                result['notes'].append('independent OCaml test file missing')
            if code == 0:
                command = ['ocamlc','-w','+8+11','-warn-error','+8+11','generated.ml']
                if test.exists():
                    (work/'test_generated.ml').write_text(test.read_text())
                    command += ['test_generated.ml','-o','test_generated']
                else:
                    command += ['-c']
                code, more = run(command, work)
                compile_log += more
            (work/'compile.log').write_text(compile_log)
            result['compiled'] = code == 0
            if code != 0:
                result['notes'].append('compiler/interface rejection; see verification/compile.log')
            elif test.exists():
                exit_code, test_log = run([str(work/'test_generated')], work)
                (work/'test.log').write_text(test_log)
                result['test_exit'] = exit_code
                result['tests'] = exit_code == 0
    except (OSError, ValueError, TypeError, KeyError) as error:
        result['notes'].append(str(error))
    result['elapsed_seconds'] = round(time.monotonic()-start, 3)
    result['status'] = classify(**{key: result[key] for key in
        ('contract', 'strength', 'synthesis', 'lowering', 'interface', 'compiled', 'tests', 'test_exit')})
    (work/'result.json').write_text(json.dumps(result, indent=2)+'\n')
    return result


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('--root', type=Path, default=BASE)
    cli.add_argument('--workers', type=int, default=4)
    args = cli.parse_args()
    metadata = read_json(args.root/'contract-results.json', [])
    if isinstance(metadata, dict):
        metadata = metadata.get('items', metadata.get('results', []))
    indexed = {row['id']: row for row in metadata if isinstance(row, dict) and 'id' in row}
    catalogue = read_json(args.root/'catalogue.json')
    declared = catalogue.get('items', [])
    if declared:
        directories = [args.root/'items'/row['id'] for row in declared]
    else:
        directories = sorted(path for path in (args.root/'items').iterdir() if path.is_dir())
    def item(directory):
        assessment = indexed.get(directory.name, read_json(directory/'assessment.json'))
        result = verify_item(directory, assessment=assessment)
        print(result['id']+': '+result['status'], flush=True)
        return result
    with ThreadPoolExecutor(max_workers=max(1, min(args.workers, 8))) as pool:
        results = list(pool.map(item, directories))
    (args.root/'results.json').write_text(json.dumps(results, indent=2)+'\n')
    counts = {}
    for result in results:
        counts[result['status']] = counts.get(result['status'], 0)+1
    text = '# OCaml exercise fulfillment results\n\n'
    text += f"Verified item records: {len(results)}. Fulfilled: {counts.get('fulfilled', 0)}.\n\n"
    text += 'A candidate is not fulfillment. Full contract, required interface, compilation and semantic-test gates must all pass. Finite tests are not a proof of all inputs.\n\n'
    text += '| Status | Count |\n|---|---:|\n'+''.join(f'| {key} | {value} |\n' for key, value in sorted(counts.items()))
    text += '\n| Exercise | Status | Contract strength |\n|---|---|---|\n'
    text += ''.join(f"| {row['id']} | {row['status']} | {row['strength']} |\n" for row in results)
    (args.root/'RESULTS.md').write_text(text)
    print(json.dumps(counts, sort_keys=True), flush=True)


if __name__ == '__main__':
    main()
