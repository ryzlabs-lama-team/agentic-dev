#!/usr/bin/env python3
"""Token and cost report for sw-factory runs, read from Claude Code's own session transcripts.

No agent reads or runs this file, so measuring a run adds nothing to any agent's context.

  python3 .claude/sw-factory/usage.py report [<run-slug>] [--by agent|phase|track|model|session|run]
                                              [--format table|json|csv]
  python3 .claude/sw-factory/usage.py snapshot
  python3 .claude/sw-factory/usage.py snapshot --hook   # SessionEnd hook: JSON on stdin, silent

Run it from the repository root, in a terminal of its own: `!` output inside a Claude session
lands in that session's context. Both commands save one summary per factory session under
<runs>/.usage/, so a report still works after Claude Code has deleted old transcripts.

Cost: when a session ends, Claude Code records its own cost per model (subagents included). That
figure is split across the session's agents by weighted tokens, so totals match Claude Code.
Usage after the last recorded cost (a session still open) is priced at the per-model rate
observed in ended sessions and marked "~".
"""
import argparse
import csv
import glob
import json
import os
import re
import sys
import time

FACTORY = ('sw-manager', 'po', 'sw-architect', 'sw-planner', 'sw-builder', 'sw-qa')
AGENT_ORDER = ('sw-manager', 'main', 'po', 'sw-architect', 'sw-planner', 'sw-builder', 'sw-qa')
# Price of each token kind relative to one uncached input token (Anthropic's price structure).
# Only used to split Claude Code's own per-model cost between agents, and to derive rates.
WEIGHT = {'input': 1.0, 'cache_write_5m': 1.25, 'cache_write_1h': 2.0, 'cache_read': 0.1, 'output': 5.0}
KINDS = ('input', 'cache_write_5m', 'cache_write_1h', 'cache_read', 'output', 'thinking', 'calls')
UNATTRIBUTED = '(unattributed)'
FACTORY_SETTING = re.compile(r'"agentSetting"\s*:\s*"(?:%s|opsx-[^"]*)"' % '|'.join(map(re.escape, FACTORY)))
LAST_KIND = re.compile(r'"type"\s*:\s*"(assistant|cost-state)"')
SCHEMA = 1


def is_factory(agent):
    return bool(agent) and (agent in FACTORY or agent.startswith('opsx-'))


# ------------------------------------------------------------------------------------- locations

def runs_dir(project):
    """`paths.runs` from .sw-factory/config.yaml (same lookup as hooks/guard.sh), no trailing slash."""
    value, in_paths = '', False
    try:
        with open(os.path.join(project, '.sw-factory', 'config.yaml'), encoding='utf-8') as f:
            for line in f:
                body = line.split('#', 1)[0]
                if line[:1] not in ('', ' ', '\t', '#', '\n', '\r'):
                    in_paths = body.strip() == 'paths:'
                elif in_paths:
                    key, _, val = body.strip().partition(':')
                    if key == 'runs':
                        value = val.strip().strip('"\'')
                        break
    except OSError:
        pass
    return (value or '.sw-factory/runs').rstrip('/')


def transcripts_dir(project):
    """Claude Code keeps a project's sessions in ~/.claude/projects/<cwd, non-alphanumerics → '-'>."""
    base = os.path.join(os.environ.get('CLAUDE_CONFIG_DIR') or os.path.expanduser('~/.claude'), 'projects')
    for path in (project, os.path.realpath(project)):
        candidate = os.path.join(base, re.sub(r'[^A-Za-z0-9]', '-', path))
        if os.path.isdir(candidate):
            return candidate
    return None


# --------------------------------------------------------------------------------------- parsing

def read_jsonl(path):
    try:
        with open(path, encoding='utf-8', errors='replace') as f:
            for line in f:
                try:
                    entry = json.loads(line)
                except ValueError:
                    continue
                if isinstance(entry, dict):
                    yield entry
    except OSError:
        return


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return '\n'.join(b.get('text') or '' for b in content if isinstance(b, dict) and b.get('type') == 'text')
    return ''


def is_tool_result(content):
    return isinstance(content, list) and any(isinstance(b, dict) and b.get('type') == 'tool_result' for b in content)


def first(pattern, text):
    m = re.search(pattern, text or '', re.M)
    return m.group(1) if m else None


def spawn_fields(prompt):
    """RUN / TRACK / MODE / ROUND / phase from a spawn prompt (sw-manager.md step 8, the playbooks)."""
    phase = (first(r'qa-(P\d+)-\d+', prompt) or first(r'#(P\d+)\b', prompt)
             or first(r'^\s*[-*]?\s*(?:WORK PACKAGE|TASK|PHASE):[^\n]*?\b(P\d+)\b', prompt))
    if not phase:  # OpenSpec change ids are <slug>-p<n>
        n = first(r'(?i)\bchange[^\n]*?[\w.]-p(\d+)\b', prompt)
        phase = 'P' + n if n else None
    run = first(r'\bRUN:\s*([A-Za-z0-9][\w.-]*)', prompt)
    return {'run': run.rstrip('.') if run else None, 'phase': phase,
            'track': first(r'\bTRACK:\s*([A-Za-z][\w-]*)', prompt),
            'mode': first(r'\bMODE:\s*([A-Za-z][\w-]*)', prompt),
            'round': first(r'\bROUND:\s*(\d+)', prompt)}


def usage_of(u):
    written = u.get('cache_creation_input_tokens') or 0
    one_hour = (u.get('cache_creation') or {}).get('ephemeral_1h_input_tokens') or 0
    return {'input': u.get('input_tokens') or 0, 'cache_write_5m': max(written - one_hour, 0),
            'cache_write_1h': one_hour, 'cache_read': u.get('cache_read_input_tokens') or 0,
            'output': u.get('output_tokens') or 0,
            'thinking': (u.get('output_tokens_details') or {}).get('thinking_tokens') or 0, 'calls': 1}


def units(tokens):
    return sum(w * (tokens.get(k) or 0) for k, w in WEIGHT.items())


def scan(path, seen):
    """One transcript file → its API calls, tool uses, spawn prompt and session markers.

    Claude Code writes one line per content block, repeating the message's usage; the first copy
    can hold a partial output count, so the last copy wins. A message id already counted in another
    file (a forked session replaying history) is skipped.
    """
    out = {'messages': [], 'tools': [], 'prompt': None, 'agent_setting': None, 'cost': None,
           'cost_pos': -1, 'compactions': [], 'version': None}
    by_id = {}
    for pos, entry in enumerate(read_jsonl(path)):
        kind = entry.get('type')
        if kind == 'assistant':
            msg = entry.get('message') or {}
            out['version'] = entry.get('version') or out['version']
            for block in msg.get('content') or []:
                if isinstance(block, dict) and block.get('type') == 'tool_use':
                    out['tools'].append((pos, block.get('id'), block.get('name'), block.get('input') or {}))
            mid = msg.get('id') or entry.get('requestId') or entry.get('uuid')
            usage, model = msg.get('usage'), msg.get('model')
            if not isinstance(usage, dict) or not model or model.startswith('<') or mid in seen:
                continue
            if mid in by_id:
                by_id[mid]['tok'] = usage_of(usage)
            else:
                by_id[mid] = {'pos': pos, 'ts': entry.get('timestamp') or '', 'model': model,
                              'tok': usage_of(usage), 'side': bool(entry.get('isSidechain'))}
                out['messages'].append(by_id[mid])
        elif kind == 'user' and out['prompt'] is None:
            content = (entry.get('message') or {}).get('content')
            if not is_tool_result(content):
                out['prompt'] = text_of(content)
        elif kind == 'agent-setting':
            out['agent_setting'] = entry.get('agentSetting')
        elif kind == 'cost-state':
            out['cost'], out['cost_pos'] = entry, pos
        elif kind == 'system' and entry.get('subtype') == 'compact_boundary':
            out['compactions'].append(pos)
    seen.update(by_id)
    return out


def looks_like_factory(main_path, runs):
    """Cheap pre-filter, so ordinary sessions in the repo are never fully parsed."""
    for meta in glob.glob(os.path.join(glob.escape(main_path[:-6]), 'subagents', '*.meta.json')):
        try:
            with open(meta, encoding='utf-8') as f:
                if is_factory(json.load(f).get('agentType')):
                    return True
        except (OSError, ValueError, AttributeError):
            continue
    try:
        with open(main_path, encoding='utf-8', errors='replace') as f:
            text = f.read()
    except OSError:
        return False
    return runs + '/' in text or bool(FACTORY_SETTING.search(text))


class Timeline:
    """The main session's current run / phase / track, from its spawns and its run-state paths."""

    def __init__(self, tools, runs):
        path_re = re.compile(r'(?<![\w.-])' + re.escape(runs) + r'/([A-Za-z0-9][\w.-]*)/')
        self.signals, self.spawn_pos = [], {}
        for pos, tool_id, name, args in tools:
            if name in ('Agent', 'Task'):
                self.spawn_pos[tool_id] = pos
                fields = spawn_fields(args.get('prompt') or '')
                self.signals.append((pos, {k: fields[k] for k in ('run', 'phase', 'track') if fields[k]}))
            else:
                target = args.get('command') if name == 'Bash' else (args.get('file_path') or args.get('notebook_path'))
                found = path_re.findall(target) if isinstance(target, str) else []
                if found:
                    self.signals.append((pos, {'run': found[-1]}))
        self.signals = [s for s in self.signals if s[1]]
        self.first_run = next((s['run'] for _, s in self.signals if s.get('run')), None)

    def at(self, pos, inclusive=False):
        state = {'run': self.first_run, 'phase': None, 'track': None}
        for sig_pos, sig in self.signals:
            if sig_pos > pos or (sig_pos == pos and not inclusive):
                break
            if sig.get('run') and sig['run'] != state['run']:
                state = {'run': sig['run'], 'phase': None, 'track': None}
            state.update(sig)
        return state


def new_record(session, agent_id, agent, ctx, depth=0, parent=None):
    return {'session': session, 'agent_id': agent_id, 'agent': agent, 'parent': parent, 'depth': depth,
            'run': ctx.get('run') or UNATTRIBUTED, 'phase': ctx.get('phase'), 'track': ctx.get('track'),
            'mode': ctx.get('mode'), 'round': ctx.get('round'), 'models': {}, 'tool_uses': 0,
            'peak_context': 0, 'compactions': 0, 'start': None, 'end': None}


def add_message(rec, msg, covered):
    tok = msg['tok']
    slot = rec['models'].setdefault(msg['model'], dict({k: 0 for k in KINDS}, units=0.0, units_tail=0.0))
    for k in KINDS:
        slot[k] += tok[k]
    slot['units' if covered else 'units_tail'] += units(tok)
    rec['peak_context'] = max(rec['peak_context'], tok['input'] + tok['cache_write_5m'] + tok['cache_write_1h'] + tok['cache_read'])
    if msg['ts']:
        rec['start'] = min(rec['start'] or msg['ts'], msg['ts'])
        rec['end'] = max(rec['end'] or msg['ts'], msg['ts'])


def analyse_session(main_path, runs, seen):
    """A factory session → summary dict, or None for a session the factory took no part in."""
    session = os.path.basename(main_path)[:-6]
    main = scan(main_path, seen)
    subs = {}
    for path in sorted(glob.glob(os.path.join(glob.escape(main_path[:-6]), 'subagents', 'agent-*.jsonl'))):
        try:
            with open(path[:-6] + '.meta.json', encoding='utf-8') as f:
                meta = json.load(f)
        except (OSError, ValueError):
            meta = {}
        subs[os.path.basename(path)[6:-6]] = (meta if isinstance(meta, dict) else {}, scan(path, seen))

    timeline = Timeline(main['tools'], runs)
    if not (is_factory(main['agent_setting']) or timeline.first_run
            or any(is_factory(meta.get('agentType')) for meta, _ in subs.values())):
        return None

    # Coverage of Claude Code's recorded cost: everything up to the last cost-state, unless the
    # session went on after it (resumed, or still open).
    tail = [m for m in main['messages'] if m['pos'] > main['cost_pos']]
    before = [m['ts'] for m in main['messages'] if m['pos'] < main['cost_pos'] and m['ts']]
    cutoff = max(before) if before else ''
    if main['cost'] is None:
        covered = lambda m, in_main: False
    elif not tail:
        covered = lambda m, in_main: True
    else:
        covered = lambda m, in_main: m['pos'] < main['cost_pos'] if in_main else bool(m['ts']) and m['ts'] <= cutoff

    records = {}
    main_agent = main['agent_setting'] or 'main'
    for msg in main['messages']:
        state = timeline.at(msg['pos'])
        agent = '(subagent)' if msg['side'] else main_agent  # pre-2.1 transcripts kept subagents inline
        rec = records.setdefault(('main', agent, state['run']), new_record(session, 'main', agent, {'run': state['run']}))
        add_message(rec, msg, covered(msg, True))
    for pos, _, _, _ in main['tools']:
        key = ('main', main_agent, timeline.at(pos)['run'])
        if key in records:
            records[key]['tool_uses'] += 1
    for pos in main['compactions']:
        key = ('main', main_agent, timeline.at(pos)['run'])
        if key in records:
            records[key]['compactions'] += 1

    resolved = {}

    def resolve(agent_id, hops=0):  # own spawn fields, else the parent's, else the main session's state
        if agent_id not in resolved:
            meta, sc = subs[agent_id]
            own = spawn_fields(sc['prompt'] or '')
            parent = meta.get('parentAgentId')
            if parent in subs and hops < 16:
                inherited = resolve(parent, hops + 1)
            else:
                inherited = timeline.at(timeline.spawn_pos.get(meta.get('toolUseId'), -1), inclusive=True)
            same_run = not own['run'] or own['run'] == inherited.get('run')
            resolved[agent_id] = dict(own, run=own['run'] or inherited.get('run'),
                                      **{k: own[k] or (inherited.get(k) if same_run else None) for k in ('phase', 'track')})
        return resolved[agent_id]

    for agent_id, (meta, sc) in subs.items():
        if not sc['messages']:
            continue
        rec = new_record(session, agent_id, meta.get('agentType') or '(subagent)', resolve(agent_id),
                         meta.get('spawnDepth') or 1, meta.get('parentAgentId'))
        for msg in sc['messages']:
            add_message(rec, msg, covered(msg, False))
        rec['tool_uses'], rec['compactions'] = len(sc['tools']), len(sc['compactions'])
        records[('sub', agent_id)] = rec

    cost_state = None
    if main['cost']:
        cost_state = {}
        for model, mu in (main['cost'].get('modelUsage') or {}).items():
            if not isinstance(mu, dict):
                continue
            written, one_hour = mu.get('cacheCreationInputTokens') or 0, mu.get('cacheCreationEphemeral1hInputTokens') or 0
            cost_state[model] = {'cost_usd': mu.get('costUSD') or 0.0, 'units': units({
                'input': mu.get('inputTokens'), 'cache_write_5m': max(written - one_hour, 0), 'cache_write_1h': one_hour,
                'cache_read': mu.get('cacheReadInputTokens'), 'output': mu.get('outputTokens')})}
    return {'schema': SCHEMA, 'session': session, 'transcript': main_path, 'version': main['version'],
            'ended': main['cost'] is not None and not tail, 'cost_state': cost_state,
            'records': list(records.values()), 'parsed_messages': len(main['messages']) + sum(len(sc['messages']) for _, sc in subs.values())}


# -------------------------------------------------------------------------------------- snapshots

def save(store, summary):
    os.makedirs(store, exist_ok=True)
    tmp = os.path.join(store, '.%s.tmp' % summary['session'])
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(summary, f, separators=(',', ':'))
    os.replace(tmp, os.path.join(store, summary['session'] + '.json'))


def load_store(store):
    out = {}
    for path in glob.glob(os.path.join(glob.escape(store), '*.json')):
        try:
            with open(path, encoding='utf-8') as f:
                summary = json.load(f)
        except (OSError, ValueError):
            continue
        if isinstance(summary, dict) and summary.get('schema') == SCHEMA and summary.get('session'):
            out[summary['session']] = summary
    return out


def collect(project, tdir, write):
    """Parse every factory session in `tdir`, oldest first, and refresh its snapshot."""
    runs = runs_dir(project)
    store = os.path.join(project, runs, '.usage')
    sessions = load_store(store)
    if not tdir:
        print('usage: no Claude Code transcripts found for %s (pass --transcripts DIR)' % project, file=sys.stderr)
        return sessions
    mains = glob.glob(os.path.join(glob.escape(tdir), '*.jsonl'))
    birth = lambda p: getattr(os.stat(p), 'st_birthtime', os.stat(p).st_mtime)
    seen = set()
    for path in sorted(mains, key=birth):
        if not looks_like_factory(path, runs):
            continue
        summary = analyse_session(path, runs, seen)
        if summary is None:
            continue
        if summary['records'] or summary['session'] not in sessions:
            sessions[summary['session']] = summary
        if summary['parsed_messages'] == 0:
            print('usage: session %s looks like a factory session but no usage parsed; transcript format '
                  'not recognised (Claude Code %s)' % (summary['session'], summary['version'] or '?'), file=sys.stderr)
        elif write:
            save(store, summary)
    return sessions


def session_ended(path):
    """True once the transcript's last cost-state comes after its last assistant message."""
    try:
        with open(path, 'rb') as f:
            f.seek(0, os.SEEK_END)
            f.seek(max(f.tell() - 262144, 0))
            tail = f.read().decode('utf-8', 'replace')
    except OSError:
        return True
    kinds = LAST_KIND.findall(tail)
    return bool(kinds) and kinds[-1] == 'cost-state'


def hook():
    """SessionEnd: snapshot this session. Never prints, never fails, returns at once."""
    try:
        data = json.loads(sys.stdin.read() or '{}')
    except ValueError:
        return
    if not isinstance(data, dict):
        return
    path = data.get('transcript_path')
    project = os.environ.get('CLAUDE_PROJECT_DIR') or data.get('cwd')
    if not (isinstance(path, str) and path.endswith('.jsonl') and isinstance(project, str)
            and os.path.isdir(os.path.join(project, '.sw-factory'))):
        return
    child = False
    if hasattr(os, 'fork'):  # SessionEnd hooks time out after 1.5 s: hand the work to a detached child
        if os.fork():
            return
        child = True
        os.setsid()
    try:
        deadline = time.time() + 5
        while time.time() < deadline and not session_ended(path):
            time.sleep(0.25)
        runs = runs_dir(project)
        if looks_like_factory(path, runs):
            summary = analyse_session(path, runs, set())
            if summary and summary['parsed_messages']:
                save(os.path.join(project, runs, '.usage'), summary)
    finally:
        if child:
            os._exit(0)


# ----------------------------------------------------------------------------------------- report

def priced(sessions):
    """Records with `cost_usd` and `estimated` set: Claude Code's figures split by weighted tokens,
    plus a per-model rate learned from ended sessions for usage after the last recorded cost."""
    spent, seen_units = {}, {}
    for s in sessions.values():
        for model, c in (s.get('cost_state') or {}).items():
            spent[model] = spent.get(model, 0.0) + c['cost_usd']
            seen_units[model] = seen_units.get(model, 0.0) + c['units']
    rate = {m: spent[m] / seen_units[m] for m in spent if seen_units.get(m)}

    records = []
    for s in sessions.values():
        recs = [dict(r, cost={m: 0.0 for m in r['models']}, estimated=False, unpriced=False) for r in s['records']]
        cost_state = s.get('cost_state') or {}
        for model, c in cost_state.items():
            total = sum(r['models'][model]['units'] for r in recs if model in r['models'])
            if total > 0:
                for r in recs:
                    if model in r['models']:
                        r['cost'][model] += c['cost_usd'] * r['models'][model]['units'] / total
            elif c['cost_usd'] > 0:  # calls the transcripts do not show (titles, summaries)
                owner = next((r for r in recs if r['agent_id'] == 'main'), recs[0] if recs else None)
                extra = new_record(s['session'], 'overhead', '(claude-code)',
                                   {'run': owner['run'] if owner else UNATTRIBUTED, 'mode': 'auxiliary'})
                extra['models'][model] = dict({k: 0 for k in KINDS}, units=0.0, units_tail=0.0)
                recs.append(dict(extra, cost={model: c['cost_usd']}, estimated=False, unpriced=False))
        for r in recs:
            for model, slot in r['models'].items():
                pending = slot['units_tail'] + (slot['units'] if model not in cost_state else 0.0)
                if pending > 0:
                    if model in rate:
                        r['cost'][model] += pending * rate[model]
                        r['estimated'] = True
                    else:
                        r['unpriced'] = True
            r['cost_usd'] = sum(r['cost'].values())
        records.extend(recs)
    return records


GROUPS = {'agent': ('run', 'phase', 'agent', 'track'), 'phase': ('run', 'phase'), 'track': ('run', 'track'),
          'model': ('run', 'model'), 'session': ('run', 'session'), 'run': ('run',)}


def sort_key(key, names):
    def part(name, value):
        if name == 'phase':
            return (0, 0) if value is None else (1, int(value[1:])) if re.match(r'P\d+$', value) else (2, value)
        if name == 'agent':
            return (AGENT_ORDER.index(value) if value in AGENT_ORDER else len(AGENT_ORDER), value)
        if name == 'run':
            return (value == UNATTRIBUTED, value)
        return (value is None, value or '')
    return tuple(part(n, v) for n, v in zip(names, key))


def group(records, by):
    names = GROUPS[by]
    rows = {}
    for r in records:
        per_model = r['models'].items() if by == 'model' else [(None, None)]
        for model, slot in per_model:
            values = dict(r, model=model)
            key = tuple(values.get(n) for n in names)
            row = rows.setdefault(key, dict(zip(names, key), instances=set(), sessions=set(), models=set(),
                                            calls=0, input=0, cache_write=0, cache_read=0, output=0,
                                            peak_context=0, cost_usd=0.0, estimated=False, unpriced=False,
                                            start=None, end=None))
            slots = [slot] if slot else list(r['models'].values())
            for s in slots:
                row['calls'] += s['calls']
                row['input'] += s['input']
                row['cache_write'] += s['cache_write_5m'] + s['cache_write_1h']
                row['cache_read'] += s['cache_read']
                row['output'] += s['output']
            row['cost_usd'] += r['cost'][model] if slot else r['cost_usd']
            row['models'].update([model] if model else r['models'].keys())
            if r['agent_id'] not in ('main', 'overhead'):
                row['instances'].add((r['session'], r['agent_id']))
            row['sessions'].add(r['session'])
            row['peak_context'] = max(row['peak_context'], r['peak_context'])
            row['estimated'] |= r['estimated']
            row['unpriced'] |= r['unpriced']
            for edge, pick in (('start', min), ('end', max)):
                if r[edge]:
                    row[edge] = pick(row[edge] or r[edge], r[edge])
    out = []
    for key in sorted(rows, key=lambda k: sort_key(k, names)):
        row = rows[key]
        row['spawns'], row['sessions'] = len(row.pop('instances')), len(row['sessions'])
        row['models'] = sorted(m.replace('claude-', '') for m in row['models'])
        out.append(row)
    return out


def human(n):
    for size, suffix in ((1e9, 'B'), (1e6, 'M'), (1e3, 'k')):
        if n >= size:
            return ('%.1f' % (n / size)).rstrip('0').rstrip('.') + suffix
    return str(int(n))


def money(row):
    if row['cost_usd'] == 0 and row['unpriced']:
        return '?'
    amount = row['cost_usd']
    return ('~' if row['estimated'] else '') + ('$%.2f' if amount >= 1 else '$%.3f') % amount + ('+?' if row['unpriced'] else '')


def print_table(rows, by, total):
    names = [n for n in GROUPS[by] if not (n == 'run' and len({r['run'] for r in rows}) == 1 and by != 'run')]
    head = [n.capitalize() for n in names] + ['Models', 'Spawns', 'Calls', 'Input', 'Cache W', 'Cache R',
                                              'Output', 'Peak ctx', 'Cost']
    body = []
    for r in rows + [total]:
        cells = [('Total' if r is total and i == 0 else '') if r is total else (str(r[n]) if r[n] is not None else '—')
                 for i, n in enumerate(names)]
        body.append(cells + [','.join(r['models']), str(r['spawns'] or '—'), str(r['calls']), human(r['input']),
                             human(r['cache_write']), human(r['cache_read']), human(r['output']),
                             human(r['peak_context']), money(r)])
    widths = [max(len(head[i]), *(len(b[i]) for b in body)) for i in range(len(head))]
    right = set(range(len(names) + 1, len(head)))
    fmt = lambda cells: '  '.join(c.rjust(w) if i in right else c.ljust(w) for i, (c, w) in enumerate(zip(cells, widths))).rstrip()
    print(fmt(head))
    for i, cells in enumerate(body):
        if i == len(body) - 1:
            print(fmt(['-' * w for w in widths]))
        print(fmt(cells))


def report(args):
    project = os.path.abspath(args.project or os.environ.get('CLAUDE_PROJECT_DIR') or os.getcwd())
    write = os.path.isdir(os.path.join(project, '.sw-factory'))
    sessions = collect(project, args.transcripts or transcripts_dir(project), write)
    records = [r for r in priced(sessions) if not args.run or r['run'] == args.run]
    if not records:
        print('No sw-factory usage found%s.' % (' for run %s' % args.run if args.run else ''), file=sys.stderr)
        return 1
    rows = group(records, args.by)
    total = group([dict(r, run='*') for r in records], 'run')[0]
    if args.format == 'json':
        json.dump({'by': args.by, 'rows': rows, 'total': total}, sys.stdout, indent=2)
        print()
    elif args.format == 'csv':
        cols = list(GROUPS[args.by]) + ['models', 'spawns', 'sessions', 'calls', 'input', 'cache_write',
                                        'cache_read', 'output', 'peak_context', 'cost_usd', 'estimated', 'start', 'end']
        w = csv.writer(sys.stdout)
        w.writerow(cols)
        for r in rows:
            w.writerow([' '.join(r[c]) if c == 'models' else (round(r[c], 4) if c == 'cost_usd' else r[c]) for c in cols])
    else:
        runs = sorted({r['run'] for r in records})
        ended = sum(1 for s in sessions.values() if s.get('ended') and any(r['session'] == s['session'] for r in records))
        days = ' · %s → %s' % (total['start'][:10], total['end'][:10]) if total['start'] else ''
        print('sw-factory usage · %s · %d session%s (%d ended)%s · %s' % (
            'run ' + runs[0] if len(runs) == 1 else '%d runs' % len(runs), total['sessions'],
            '' if total['sessions'] == 1 else 's', ended, days, money(total)))
        print()
        print_table(rows, args.by, total)
        print()
        print('Cost: Claude Code\'s own per-model figures, split by weighted tokens. ~ = includes usage priced at '
              'the rate seen in ended sessions; ? = no rate known for that model yet.')
    return 0


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if argv[:1] == ['snapshot'] and '--hook' in argv:
        try:
            hook()
        except BaseException:  # a measurement hook must never disturb the session
            pass
        return 0
    ap = argparse.ArgumentParser(description='Token and cost report for sw-factory runs.')
    sub = ap.add_subparsers(dest='cmd')
    rep = sub.add_parser('report', help='print usage by run, phase, agent, track, model or session')
    rep.add_argument('run', nargs='?', help='run slug (default: every run)')
    rep.add_argument('--by', choices=sorted(GROUPS), default='agent')
    rep.add_argument('--format', choices=('table', 'json', 'csv'), default='table')
    snap = sub.add_parser('snapshot', help='save a summary of every factory session under <runs>/.usage/')
    snap.add_argument('--hook', action='store_true', help='SessionEnd hook mode: hook JSON on stdin, silent, always exits 0')
    for p in (rep, snap):
        p.add_argument('--transcripts', help='Claude Code transcript directory (default: derived from the project path)')
        p.add_argument('--project', help='repository root (default: $CLAUDE_PROJECT_DIR or the current directory)')
    args = ap.parse_args(argv)
    if args.cmd == 'report':
        return report(args)
    if args.cmd == 'snapshot':
        project = os.path.abspath(args.project or os.environ.get('CLAUDE_PROJECT_DIR') or os.getcwd())
        if not os.path.isdir(os.path.join(project, '.sw-factory')):
            print('usage: %s has no .sw-factory/; run from the repository root' % project, file=sys.stderr)
            return 1
        print('%d factory session(s) saved' % len(collect(project, args.transcripts or transcripts_dir(project), True)))
        return 0
    ap.print_help()
    return 1


if __name__ == '__main__':
    sys.exit(main())
