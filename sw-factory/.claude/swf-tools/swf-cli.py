#!/usr/bin/env python3
"""swf-cli: deterministic bookkeeping for the sw-factory agents.

Agents run this instead of doing mechanical work themselves: ticking plan tasks, keeping the run
ledger, bumping document versions, numbering ADRs and clarifications, checking traceability,
measuring changed-lines coverage, checking document drift, computing a work item's level, and
running the gate commands. Run it from the repository root:

  python3 .claude/swf-tools/swf-cli.py <group> <command> …      (--help on any level)

Output is terse `key: value` lines meant to be pasted into a return payload. It never prints a
document body or a diff. Exit codes:
  0  ok
  1  the check found problems (drift, gaps, budget exhausted, a failing gate)
  2  usage or input error
  3  unmeasurable (coverage could not be measured: treat as GATE UNMEASURABLE)

Python 3.8+, standard library only.
"""
import argparse
import datetime
import fnmatch
import json
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

VERSION = '1.0.0'
HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATES = os.path.join(HERE, 'templates')
RETRY_BUDGET = 2          # QA retry rounds per work item (swf-manager "Retry budget")
CLAR_BUDGET = 5           # clarification questions per work package (clarification protocol)


class Fail(Exception):
    def __init__(self, msg, code=2):
        super().__init__(msg)
        self.code = code


def today():
    return datetime.date.today().isoformat()


def root():
    return os.getcwd()


# ========================================================================================= config

DEFAULTS = {
    'paths': {'prds': 'docs/prds', 'tech_designs': 'docs/tech-designs', 'adrs': 'docs/adrs',
              'plans': 'docs/plans', 'ops_docs': 'docs/operations', 'runs': '.sw-factory/runs'},
    'gates': {'coverage_min': '90', 'coverage_scope': 'changed', 'tests_passing': '100',
              'build_passing': 'true', 'test_globs': []},
    'commands': {'build': '', 'test': '', 'coverage': '', 'lint': ''},
    'human_gates': {},
    'tracks': {'enabled': ['direct', 'subagents', 'opsx-loop', 'openspec'], 'opsx_archive': 'ask'},
    'git': {'commit': 'ask'},
}


def _scalar(v):
    v = v.strip()
    if v.startswith('[') and v.endswith(']'):
        return [_scalar(x) for x in v[1:-1].split(',') if x.strip()]
    if len(v) >= 2 and v[0] == v[-1] and v[0] in '"\'':
        return v[1:-1]
    return v


def load_config():
    """`.sw-factory/config.yaml`: two-level mappings plus inline lists, the subset the config uses.
    Same reading rules as hooks/guard.sh and usage.py: comments dropped, quotes stripped."""
    cfg = {k: dict(v) for k, v in DEFAULTS.items()}
    path = os.path.join(root(), '.sw-factory', 'config.yaml')
    try:
        with open(path, encoding='utf-8') as f:
            lines = f.read().splitlines()
    except OSError:
        lines = []
    section = None
    for line in lines:
        body = line.split('#', 1)[0].rstrip()
        if not body.strip():
            continue
        if not line[:1].isspace():
            key, _, val = body.partition(':')
            section = key.strip() if not val.strip() else None
            if section:
                cfg.setdefault(section, {})
            continue
        if section:
            key, sep, val = body.strip().partition(':')
            if sep and val.strip():
                cfg[section][key.strip()] = _scalar(val)
    for k, v in cfg['paths'].items():
        cfg['paths'][k] = str(v).rstrip('/') or DEFAULTS['paths'].get(k, '')
    return cfg


CFG = None


def cfg():
    global CFG
    if CFG is None:
        CFG = load_config()
    return CFG


def P(key):
    return cfg()['paths'][key]


# ============================================================================== paths and files

def rel(path):
    """A project-relative path (symlinks resolved), or the absolute path if outside the project."""
    full = os.path.realpath(os.path.join(root(), path))
    base = os.path.realpath(root())
    if full == base or full.startswith(base + os.sep):
        return os.path.relpath(full, base).replace(os.sep, '/')
    return full


def under(relpath, *dirs):
    return any(relpath == d or relpath.startswith(d.rstrip('/') + '/') for d in dirs)


def require_under(path, dirs, what):
    r = rel(path)
    if not under(r, *dirs):
        raise Fail('%s must be under %s: %s' % (what, ' or '.join(d + '/' for d in dirs), r))
    return r


def read(path):
    try:
        with open(os.path.join(root(), path), encoding='utf-8') as f:
            return f.read()
    except OSError as e:
        raise Fail('cannot read %s: %s' % (path, e.strerror))


def write(path, text):
    full = os.path.join(root(), path)
    os.makedirs(os.path.dirname(full) or '.', exist_ok=True)
    with open(full, 'w', encoding='utf-8') as f:
        f.write(text)


def run_dir(slug):
    if not re.match(r'^[A-Za-z0-9][A-Za-z0-9._-]*$', slug or ''):
        raise Fail('invalid run slug: %r' % slug)
    return '%s/%s' % (P('runs'), slug)


def ledger_path(slug):
    return run_dir(slug) + '/ledger.md'


# ============================================================================================ git

def git(*args, check=True):
    try:
        r = subprocess.run(('git',) + args, cwd=root(), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True, encoding='utf-8', errors='replace')
    except OSError:
        raise Fail('git not found')
    if check and r.returncode != 0:
        raise Fail('git %s: %s' % (' '.join(args), r.stderr.strip() or 'failed'))
    return r.stdout if r.returncode == 0 else None


def verify_base(base):
    if git('rev-parse', '--verify', '--quiet', base + '^{commit}', check=False) is None:
        raise Fail('BASE is not a commit: %s' % base)


def git_show(base, path):
    return git('show', '%s:%s' % (base, path), check=False)


def changed_files(base):
    """[(status, path)] changed since BASE: tracked (vs the working tree) plus untracked ('?').
    Run state is always excluded."""
    verify_base(base)
    out = []
    for line in git('diff', '--name-status', '--no-renames', base).splitlines():
        st, _, path = line.partition('\t')
        if path:
            out.append((st[:1], path))
    for path in git('ls-files', '--others', '--exclude-standard').splitlines():
        if path:
            out.append(('?', path))
    runs = P('runs')
    return [(s, p) for s, p in out if not under(p, runs)]


def changed_lines(base, path, status):
    """The set of line numbers of <path> that changed since BASE (all lines if untracked)."""
    if status == '?':
        try:
            with open(os.path.join(root(), path), encoding='utf-8', errors='replace') as f:
                return set(range(1, sum(1 for _ in f) + 1))
        except OSError:
            return set()
    lines = set()
    for m in re.finditer(r'^@@ -\S+ \+(\d+)(?:,(\d+))? @@', git('diff', '-U0', '--no-renames', base, '--', path),
                         re.M):
        start, count = int(m.group(1)), int(m.group(2) if m.group(2) is not None else 1)
        lines.update(range(start, start + count))
    return lines


def added_lines(base, path, status):
    """[(line number, text)] added since BASE (every line if untracked)."""
    if status == '?':
        try:
            with open(os.path.join(root(), path), encoding='utf-8', errors='replace') as f:
                return [(i, t.rstrip('\n')) for i, t in enumerate(f, 1)]
        except OSError:
            return []
    out, n = [], 0
    for line in git('diff', '-U0', '--no-renames', base, '--', path).splitlines():
        m = re.match(r'^@@ -\S+ \+(\d+)', line)
        if m:
            n = int(m.group(1))
        elif line.startswith('+') and not line.startswith('+++'):
            out.append((n, line[1:]))
            n += 1
    return out


def ranges(nums):
    nums, out = sorted(nums), []
    for n in nums:
        if out and n == out[-1][1] + 1:
            out[-1][1] = n
        else:
            out.append([n, n])
    return ','.join(str(a) if a == b else '%d-%d' % (a, b) for a, b in out)


# ======================================================================================= markdown

FENCE_OPEN = re.compile(r'^ {0,3}(`{3,}|~{3,})(.*)$')


def fence_mask(lines):
    """True for lines inside (or delimiting) a fenced code block, per CommonMark: a fence is at
    most 3 spaces indented; a backtick fence's info string has no backticks (so inline code such
    as ```` ```ts ```` is not a fence); it closes on the same character, at least as long, with
    nothing but whitespace after."""
    mask, fence = [], None
    for line in lines:
        m = FENCE_OPEN.match(line)
        if fence is None:
            if m and not (m.group(1)[0] == '`' and '`' in m.group(2)):
                fence = m.group(1)
                mask.append(True)
            else:
                mask.append(False)
        else:
            mask.append(True)
            if (m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence)
                    and not m.group(2).strip()):
                fence = None
    return mask


def headings(lines):
    """[(index, level, text)] outside code fences."""
    mask = fence_mask(lines)
    out = []
    for i, line in enumerate(lines):
        m = re.match(r'^(#{1,6})\s+(.*?)\s*$', line)
        if m and not mask[i]:
            out.append((i, len(m.group(1)), m.group(2)))
    return out


def section(lines, pattern, level=None):
    """(start, end) of the first heading matching <pattern> (regex on its text), up to the next
    heading of the same or a higher level. None if absent."""
    hs = headings(lines)
    for n, (i, lvl, text) in enumerate(hs):
        if (level is None or lvl == level) and re.search(pattern, text):
            end = len(lines)
            for j, l2, _ in hs[n + 1:]:
                if l2 <= lvl:
                    end = j
                    break
            return i, end
    return None


def sections(lines, pattern, level):
    """[(match, start, end)] for every heading at <level> whose text matches <pattern>."""
    hs = headings(lines)
    out = []
    for n, (i, lvl, text) in enumerate(hs):
        m = re.match(pattern, text) if lvl == level else None
        if m:
            end = len(lines)
            for j, l2, _ in hs[n + 1:]:
                if l2 <= lvl:
                    end = j
                    break
            out.append((m, i, end))
    return out


def split_row(line):
    s = line.strip()
    if s.startswith('|'):
        s = s[1:]
    if s.endswith('|') and not s.endswith('\\|'):
        s = s[:-1]
    cells, cur, i = [], '', 0
    while i < len(s):
        if s[i] == '\\' and i + 1 < len(s) and s[i + 1] == '|':
            cur += '|'
            i += 2
            continue
        if s[i] == '|':
            cells.append(cur.strip())
            cur = ''
        else:
            cur += s[i]
        i += 1
    cells.append(cur.strip())
    return cells


def fmt_row(cells):
    return '| ' + ' | '.join(str(c).replace('\n', ' ').replace('|', '\\|') for c in cells) + ' |'


class Table:
    """The first pipe table inside lines[start:end]."""

    def __init__(self, lines, start, end):
        self.lines = lines
        i = start
        while i < end and not lines[i].lstrip().startswith('|'):
            i += 1
        if i + 1 >= end or not re.match(r'^\s*\|?\s*:?-{2,}', lines[i + 1]):
            raise Fail('no table found')
        self.head = i
        self.header = split_row(lines[i])
        j = i + 2
        while j < len(lines) and lines[j].lstrip().startswith('|'):
            j += 1
        self.end = j

    def col(self, *names):
        lower = [h.lower() for h in self.header]
        for n in names:
            if n.lower() in lower:
                return lower.index(n.lower())
        raise Fail('table has no %s column (has: %s)' % ('/'.join(names), ', '.join(self.header)))

    def has(self, name):
        return name.lower() in [h.lower() for h in self.header]

    def rows(self):
        """[(line index, cells)], padded to the header width."""
        out = []
        for i in range(self.head + 2, self.end):
            cells = split_row(self.lines[i])
            out.append((i, cells + [''] * (len(self.header) - len(cells))))
        return out

    def dicts(self):
        return [{h: c for h, c in zip(self.header, cells)} for _, cells in self.rows()]

    def append(self, cells):
        self.lines.insert(self.end, fmt_row(cells))
        self.end += 1

    def replace(self, idx, cells):
        self.lines[idx] = fmt_row(cells)


def table_under(lines, heading_pattern):
    sec = section(lines, heading_pattern)
    if not sec:
        raise Fail('no "%s" section' % re.sub(r'\(.*?\)\??|\\b|[\^$]', '', heading_pattern).strip())
    return Table(lines, sec[0] + 1, sec[1])


def is_placeholder(cells):
    return any('<' in c and '>' in c for c in cells[:1])


# =================================================================================== front matter

FM_LINE = re.compile(r'^([A-Za-z_][\w-]*):(?:(\s*)(.*?))?(\s+#.*)?$')


def fm_bounds(lines):
    if not lines or lines[0].strip() != '---':
        return None
    for i in range(1, len(lines)):
        if lines[i].strip() == '---':
            return 0, i
    return None


def fm_value(raw):
    raw = (raw or '').strip()
    if raw in ('~', 'null', ''):
        return None
    return _scalar(raw)


def front_matter(text):
    """Top-level front-matter keys (nested keys are skipped)."""
    lines = text.splitlines()
    b = fm_bounds(lines)
    out = {}
    if not b:
        return out
    for line in lines[b[0] + 1:b[1]]:
        if line[:1].isspace():
            continue
        m = FM_LINE.match(line)
        if m:
            out[m.group(1)] = fm_value(m.group(3))
    return out


def fm_format(value):
    if value in ('~', 'null', '') or value is None:
        return '~'
    if value.startswith('[') and value.endswith(']'):
        return value
    if re.search(r':\s|\s#|^[\[\]{}&*!|>\'"%@`,?-]|:$', value):
        return '"%s"' % value.replace('\\', '\\\\').replace('"', '\\"')
    return value


def fm_set(lines, key, value):
    """Set a top-level front-matter key in place, keeping its comment column. Returns the old value."""
    b = fm_bounds(lines)
    if not b:
        raise Fail('document has no front matter')
    new = fm_format(value)
    for i in range(b[0] + 1, b[1]):
        m = FM_LINE.match(lines[i])
        if m and m.group(1) == key and not lines[i][:1].isspace():
            old = fm_value(m.group(3))
            head = '%s: %s' % (key, new)
            comment = m.group(4)
            if comment:
                col = len(lines[i]) - len(comment.lstrip())
                head = head + ' ' * max(1, col - len(head)) + comment.lstrip()
            lines[i] = head
            return old
    lines.insert(b[1], '%s: %s' % (key, new))
    return None


def to_text(lines, original):
    return '\n'.join(lines) + ('\n' if original.endswith('\n') else '')


# =========================================================================================== plan

TASK = re.compile(r'^(\s*[-*]\s+\[)([ xX])(\]\s+\*\*)([\w.\-]+)(\*\*.*)$')


def plan_phases(lines):
    """{phase id: (start, end)} for the `## P<n> — …` sections."""
    return {m.group(1): (s, e) for m, s, e in sections(lines, r'(P\d+)\b', 2)}


def phase_tasks(lines, start, end):
    """[(line index, task id, done)] in a phase section."""
    mask = fence_mask(lines)
    out = []
    for i in range(start, end):
        m = TASK.match(lines[i])
        if m and not mask[i]:
            out.append((i, m.group(4), m.group(2) != ' '))
    return out


def load_plan(path):
    text = read(path)
    lines = text.splitlines()
    phases = plan_phases(lines)
    if not phases:
        raise Fail('no "## P<n>" phase sections in %s' % path)
    return text, lines, phases


def get_phase(phases, pid, path):
    pid = pid.upper()
    if pid not in phases:
        raise Fail('%s has no phase %s (has: %s)' % (path, pid, ' '.join(phases)))
    return phases[pid]


def cmd_plan_status(a):
    _, lines, phases = load_plan(a.plan)
    ids = [a.phase.upper()] if a.phase else list(phases)
    done_all = total_all = 0
    for pid in ids:
        s, e = get_phase(phases, pid, a.plan)
        tasks = phase_tasks(lines, s, e)
        done = sum(1 for t in tasks if t[2])
        done_all += done
        total_all += len(tasks)
        open_ids = [t[1] for t in tasks if not t[2]]
        print('%s tasks %d/%d · %s' % (pid, done, len(tasks), 'open: ' + ' '.join(open_ids) if open_ids else 'all ticked'))
    if not a.phase:
        print('TOTAL %d/%d' % (done_all, total_all))
    return 0


def cmd_plan_tick(a):
    require_under(a.plan, [P('plans')], 'plan')
    text, lines, phases = load_plan(a.plan)
    s, e = get_phase(phases, a.phase, a.plan)
    tasks = {t[1]: t for t in phase_tasks(lines, s, e)}
    unknown = [t for t in a.tasks if t not in tasks]
    if unknown:
        print('unknown task ids in %s: %s (has: %s)' % (a.phase.upper(), ' '.join(unknown), ' '.join(tasks)))
        print('nothing ticked')
        return 1
    ticked, already = [], []
    for tid in a.tasks:
        i, _, done = tasks[tid]
        if done:
            already.append(tid)
            continue
        lines[i] = TASK.sub(lambda m: m.group(1) + 'x' + m.group(3) + m.group(4) + m.group(5), lines[i])
        ticked.append(tid)
    if ticked:
        write(a.plan, to_text(lines, text))
    tasks = phase_tasks(lines, s, e)
    print('ticked: %s%s' % (' '.join(ticked) or 'none', ' · already ticked: ' + ' '.join(already) if already else ''))
    print('%s tasks %d/%d' % (a.phase.upper(), sum(1 for t in tasks if t[2]), len(tasks)))
    return 0


def phase_map(lines):
    return table_under(lines, r'^Phase map\b')


def cmd_plan_phases(a):
    text = read(a.plan)
    lines = text.splitlines()
    fm = front_matter(text)
    print('PLAN: %s v%s (%s)' % (a.plan, fm.get('version') or '?', fm.get('status') or '?'))
    t = phase_map(lines)
    for _, cells in t.rows():
        if not is_placeholder(cells):
            print(' · '.join(c or '—' for c in cells))
    return 0


def ledger_phases(path):
    lines = read(path).splitlines()
    t = table_under(lines, r'^Phases$')
    pc, sc = t.col('Phase'), t.col('Status')
    return {cells[pc].upper(): cells[sc] for _, cells in t.rows() if cells[pc] and not is_placeholder(cells)}


def cmd_plan_sync(a):
    require_under(a.plan, [P('plans')], 'plan')
    text = read(a.plan)
    lines = text.splitlines()
    status = ledger_phases(a.ledger)
    t = phase_map(lines)
    pc, sc = t.col('Phase'), t.col('Status')
    changes, plan_ids = [], []
    for idx, cells in t.rows():
        pid = cells[pc].upper()
        if is_placeholder(cells) or not pid:
            continue
        plan_ids.append(pid)
        want = status.get(pid)
        if want and want != cells[sc]:
            changes.append('%s %s → %s' % (pid, cells[sc] or '—', want))
            cells[sc] = want
            t.replace(idx, cells)
    fm = front_matter(text)
    cur = fm.get('status')
    states = [status.get(p, 'todo') for p in plan_ids]
    if plan_ids and all(s == 'done' for s in states):
        want = 'done'
    elif any(s in ('in-progress', 'done', 'blocked') for s in states):
        want = 'in-progress'
    else:
        want = cur
    if cur in ('approved', 'in-progress', 'done') and want != cur:
        fm_set(lines, 'status', want)
        changes.append('status %s → %s' % (cur, want))
    missing = [p for p in status if p not in plan_ids]
    if changes:
        write(a.plan, to_text(lines, text))
    print('synced: %s' % ('; '.join(changes) if changes else 'no changes'))
    if missing:
        print('warning: ledger phases not in the plan Phase map: %s' % ' '.join(missing))
    return 0


# ========================================================================================= ledger

HEADER_FIELDS = {'request': 'Request', 'started': 'Started', 'base': 'Base ref', 'branch': 'Branch',
                 'entry': 'Entry point', 'level': 'Level', 'tracks': 'Tracks available',
                 'commit': 'Commit policy'}


def set_header(lines, label, value):
    for i, line in enumerate(lines):
        if line.lower().startswith(label.lower() + ':'):
            lines[i] = '%s: %s' % (label, value)
            return
        if line.startswith('## '):
            break
    # Field missing (an older ledger): insert it after the last header line.
    j = 1
    while j < len(lines) and re.match(r'^[A-Z][\w ]*:', lines[j]):
        j += 1
    lines.insert(j, '%s: %s' % (label, value))


def get_header(lines, label):
    for line in lines:
        if line.lower().startswith(label.lower() + ':'):
            return line.split(':', 1)[1].strip()
    return ''


def load_ledger(slug):
    path = ledger_path(slug)
    if not os.path.exists(os.path.join(root(), path)):
        raise Fail('no ledger for run %s (%s); run: swf-cli.py ledger init' % (slug, path))
    text = read(path)
    return path, text, text.splitlines()


def tracks_line():
    pre = os.path.join(HERE, 'preflight.sh')
    try:
        r = subprocess.run(['bash', pre], cwd=root(), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                           universal_newlines=True)
    except OSError:
        return 'unknown (preflight not runnable)'
    for line in r.stdout.splitlines():
        if line.startswith('TRACKS:'):
            return line[len('TRACKS:'):].strip()
    return 'unknown (preflight printed no TRACKS line)'


def cmd_ledger_init(a):
    path = ledger_path(a.slug)
    if os.path.exists(os.path.join(root(), path)):
        print('ledger exists: %s (use: ledger summary %s)' % (path, a.slug))
        return 1
    tpl = read(os.path.join(TEMPLATES, 'ledger.md'))
    lines = tpl.splitlines()
    lines[0] = '# Run: %s' % a.slug
    head = git('rev-parse', 'HEAD', check=False)
    branch = git('rev-parse', '--abbrev-ref', 'HEAD', check=False)
    tracks = a.tracks or tracks_line()
    if tracks.startswith('TRACKS:'):
        tracks = tracks[len('TRACKS:'):].strip()
    values = {'Request': ' '.join(a.request.split()), 'Started': today(),
              'Base ref': head.strip() if head else 'no git', 'Branch': branch.strip() if branch else 'no git',
              'Entry point': a.entry, 'Level': 'pending triage', 'Tracks available': tracks,
              'Commit policy': cfg()['git'].get('commit', 'ask')}
    for label, value in values.items():
        set_header(lines, label, value)
    write(path, to_text(lines, tpl))
    print('LEDGER: %s' % path)
    print('base: %s · branch: %s · commit: %s' % (values['Base ref'][:12], values['Branch'], values['Commit policy']))
    print('TRACKS: %s' % tracks)
    return 0


def cmd_ledger_set(a):
    path, text, lines = load_ledger(a.slug)
    label = HEADER_FIELDS.get(a.field.lower(), a.field)
    set_header(lines, label, ' '.join(a.value.split()))
    write(path, to_text(lines, text))
    print('%s: %s' % (label, ' '.join(a.value.split())))
    return 0


def cmd_ledger_frame(a):
    path, text, lines = load_ledger(a.slug)
    done = []
    for label, value in (('Problem', a.problem), ('Goals', a.goals), ('Context', a.context)):
        if value is None:
            continue
        for i, line in enumerate(lines):
            if line.startswith('- **%s:**' % label):
                lines[i] = '- **%s:** %s' % (label, ' '.join(value.split()))
                done.append(label.lower())
                break
    write(path, to_text(lines, text))
    print('frame set: %s' % (', '.join(done) or 'nothing'))
    return 0


def next_number(t, colname='#'):
    c = t.col(colname)
    nums = [int(cells[c]) for _, cells in t.rows() if cells[c].isdigit()]
    return max(nums) + 1 if nums else 1


def cmd_ledger_log(a):
    path, text, lines = load_ledger(a.slug)
    t = table_under(lines, r'^Log$')
    n = next_number(t)
    row = [''] * len(t.header)
    for name, value in (('#', str(n)), ('Stage', a.stage), ('Agent', a.agent),
                        ('Agent id', a.agent_id or '—'), ('Status', a.status),
                        ('Artifact', a.artifact or '—'), ('Notes', a.notes or '')):
        if t.has(name):
            row[t.col(name)] = value
    t.append(row)
    write(path, to_text(lines, text))
    print('log #%d' % n)
    return 0


def doc_kind(r):
    name = r.rsplit('/', 1)[-1]
    if under(r, P('prds')):
        return {'prd.md': 'PRD', 'stories.md': 'stories'}.get(name, 'requirements')
    if under(r, P('tech_designs')):
        return 'HLD' if name == 'hld.md' else 'LLD' if name.startswith('lld') else 'design'
    if under(r, P('adrs')):
        return 'ADR'
    if under(r, P('plans')):
        return 'plan'
    if under(r, 'openspec'):
        return 'openspec'
    return 'doc'


def cmd_ledger_doc(a):
    path, text, lines = load_ledger(a.slug)
    t = table_under(lines, r'^Documents$')
    pcol = t.col('Path')
    existing = {cells[pcol]: idx for idx, cells in t.rows()}
    for doc in a.paths:
        r = rel(doc)
        fm = front_matter(read(r)) if os.path.isfile(os.path.join(root(), r)) else {}
        version = fm.get('version') or ''
        status = fm.get('status') or ('deleted' if not os.path.exists(os.path.join(root(), r)) else '')
        values = {'Kind': a.kind or doc_kind(r), 'Path': r, 'Version': version, 'Status': status,
                  'Written by': a.written_by}
        row = [values.get(h, '') for h in t.header]
        if r in existing:
            t.replace(existing[r], row)
            action = 'updated'
        else:
            t.append(row)
            existing[r] = t.end - 1
            action = 'added'
        print('doc %s %s%s%s · %s' % (values['Kind'], r, ' v' + version if version else '',
                                      ' (%s)' % status if status else '', action))
    write(path, to_text(lines, text))
    return 0


def phase_row(t, pid):
    pc = t.col('Phase')
    for idx, cells in t.rows():
        if cells[pc].upper() == pid:
            return idx, cells
    return None, None


def retries_col(t):
    return t.col('Retries', 'QA rounds')


def cmd_ledger_phase(a):
    path, text, lines = load_ledger(a.slug)
    t = table_under(lines, r'^Phases$')
    pid = a.phase.upper()
    idx, cells = phase_row(t, pid)
    if idx is None:
        cells = [''] * len(t.header)
        cells[t.col('Phase')] = pid
        cells[retries_col(t)] = '0'
    for name, value in (('Level', a.level), ('Track', a.track), ('Status', a.status),
                        ('Base ref', a.base), ('Notes', a.notes)):
        if value is not None:
            cells[t.col(name)] = value
    rc = retries_col(t)
    retries = int(cells[rc]) if cells[rc].isdigit() else 0
    code, extra = 0, ''
    if a.retry:
        if retries >= RETRY_BUDGET:
            code = 1
            extra = 'budget exhausted: %d/%d retries used · stop and report to the human' % (retries, RETRY_BUDGET)
        else:
            retries += 1
            cells[rc] = str(retries)
            extra = 'retry %d/%d · QA ROUND: %d · builder model: %s' % (
                retries, RETRY_BUDGET, retries, 'opus' if retries >= RETRY_BUDGET else 'default')
    if idx is None:
        t.append(cells)
    else:
        t.replace(idx, cells)
    write(path, to_text(lines, text))
    print('%s · %s · %s · %s · retries %s' % (pid, cells[t.col('Level')] or '—', cells[t.col('Track')] or '—',
                                              cells[t.col('Status')] or '—', cells[rc] or '0'))
    if extra:
        print(extra)
    return code


def cmd_ledger_decision(a):
    path, text, lines = load_ledger(a.slug)
    t = table_under(lines, r'^Human decisions$')
    n = next_number(t)
    values = {'#': str(n), 'Gate / question': a.gate, 'Decision': a.decision, 'Recorded in': a.recorded_in or '—'}
    t.append([values.get(h, '') for h in t.header])
    write(path, to_text(lines, text))
    print('decision #%d' % n)
    return 0


def cmd_ledger_summary(a):
    path, text, lines = load_ledger(a.slug)
    h = {k: get_header(lines, v) for k, v in HEADER_FIELDS.items()}
    print('RUN: %s · entry: %s · level: %s · base: %s · branch: %s · commit: %s' % (
        a.slug, h['entry'] or '?', h['level'] or '?', h['base'][:12] or '?', h['branch'] or '?', h['commit'] or '?'))
    req = h['request']
    print('REQUEST: %s' % (req if len(req) <= 140 else req[:137] + '…'))
    print('TRACKS: %s' % (h['tracks'] or '?'))
    phases = table_under(lines, r'^Phases$')
    prow = [c for c in phases.dicts() if c.get('Phase') and not is_placeholder([c.get('Phase')])]
    if prow:
        rk = 'Retries' if phases.has('Retries') else 'QA rounds'
        print('PHASES: ' + ' | '.join('%s %s %s %s r%s' % (r['Phase'], r.get('Level') or '—', r.get('Track') or '—',
                                                           r.get('Status') or '—', r.get(rk) or '0') for r in prow))
    else:
        print('PHASES: none')
    docs = table_under(lines, r'^Documents$').dicts()
    print('DOCS: %d%s' % (len(docs), (' (' + ', '.join('%s v%s' % (d.get('Kind'), d.get('Version') or '?')
                                                        for d in docs[:6]) + (', …' if len(docs) > 6 else '') + ')')
                          if docs else ''))
    log = table_under(lines, r'^Log$').dicts()
    for r in log[-3:]:
        print('LOG #%s %s · %s · %s%s' % (r.get('#'), r.get('Stage'), r.get('Agent'), r.get('Status'),
                                          ' · ' + r['Artifact'] if r.get('Artifact') not in (None, '', '—') else ''))
    dec = table_under(lines, r'^Human decisions$').dicts()
    print('DECISIONS: %d%s' % (len(dec), ' (last: %s → %s)' % (dec[-1].get('Gate / question'), dec[-1].get('Decision'))
                               if dec else ''))
    pending = [r for r in prow if r.get('Status') != 'done']
    if not prow:
        nxt = 'no phases recorded yet'
    elif pending:
        nxt = '%s (%s)' % (pending[0]['Phase'], pending[0].get('Status') or 'todo')
    else:
        nxt = 'all phases done'
    print('NEXT: %s' % nxt)
    return 0


# =========================================================================================== docs

def doc_dirs():
    return [P('prds'), P('tech_designs'), P('adrs'), P('plans')]


def cmd_doc_meta(a):
    code = 0
    for path in a.paths:
        r = rel(path)
        if not os.path.isfile(os.path.join(root(), r)):
            print('%s missing' % r)
            code = 1
            continue
        fm = front_matter(read(r))
        keys = a.field or [k for k in ('id', 'status', 'version', 'approved_by', 'agreed_by', 'deciders') if k in fm]
        vals = []
        for k in keys:
            v = fm.get(k)
            vals.append('%s=%s' % (k, ','.join(v) if isinstance(v, list) else ('~' if v is None else v)))
        print('%s %s' % (r, ' '.join(vals) or '(no front matter)'))
    return code


def cmd_doc_set(a):
    r = require_under(a.path, doc_dirs(), 'document')
    text = read(r)
    lines = text.splitlines()
    for kv in a.pairs:
        key, sep, value = kv.partition('=')
        if not sep or not re.match(r'^[A-Za-z_][\w-]*$', key):
            raise Fail('expected key=value, got %r' % kv)
        old = fm_set(lines, key, value)
        print('%s: %s → %s' % (key, '~' if old is None else old, fm_format(value)))
    write(r, to_text(lines, text))
    return 0


def changelog_append(lines, version, change, trigger, date):
    t = table_under(lines, r'^(\d+\.\s*)?Changelog$')
    values = {'version': version, 'date': date, 'change': change, 'reason': trigger, 'trigger': trigger}
    t.append([values.get(h.lower(), '') for h in t.header])


def cmd_doc_bump(a):
    r = require_under(a.path, doc_dirs(), 'document')
    text = read(r)
    lines = text.splitlines()
    cur = front_matter(text).get('version') or '0.0.0'
    m = re.match(r'^(\d+)\.(\d+)\.(\d+)$', str(cur))
    if not m:
        raise Fail('version is not x.y.z: %s' % cur)
    x, y, z = map(int, m.groups())
    new = {'major': (x + 1, 0, 0), 'minor': (x, y + 1, 0), 'patch': (x, y, z + 1)}[a.part]
    new = '%d.%d.%d' % new
    changelog_append(lines, new, a.change, a.trigger or '', a.date or today())
    fm_set(lines, 'version', new)
    for kv in a.set or []:
        key, _, value = kv.partition('=')
        fm_set(lines, key, value)
    write(r, to_text(lines, text))
    print('%s v%s → v%s · changelog row added' % (r, cur, new))
    return 0


def cmd_doc_decide(a):
    r = require_under(a.path, doc_dirs(), 'document')
    text = read(r)
    lines = text.splitlines()
    t = table_under(lines, r'^(\d+\.\s*)?Decision log$')
    values = {'date': a.date or today(), 'decision': a.decision, 'decided by': a.by, 'source': a.source}
    t.append([values.get(h.lower(), '') for h in t.header])
    write(r, to_text(lines, text))
    print('%s · decision-log row added' % r)
    return 0


def cmd_doc_versions(a):
    rows = []
    for st, path in changed_files(a.since):
        if not under(path, *doc_dirs()) or not path.endswith('.md'):
            continue
        new = front_matter(read(path)).get('version') if st != 'D' else None
        old_text = git_show(a.since, path) if st not in ('?', 'A') else None
        old = front_matter(old_text).get('version') if old_text else None
        if st == 'D':
            rows.append('%s deleted (was v%s)' % (path, old or '?'))
        elif old is None:
            rows.append('%s new%s' % (path, ' v' + new if new else ''))
        elif new != old:
            rows.append('%s v%s → v%s' % (path, old, new))
        elif new:
            rows.append('%s v%s (content changed, version not bumped)' % (path, new))
        else:
            rows.append('%s changed' % path)
    print('DOCUMENTS CHANGED: %d' % len(rows))
    for r in rows:
        print('  ' + r)
    return 0


# ============================================================================================= ids

def cmd_id_next(a):
    kind = a.kind
    if kind == 'adr':
        d = os.path.join(root(), P('adrs'))
        nums = [int(m.group(1)) for f in (os.listdir(d) if os.path.isdir(d) else [])
                for m in [re.match(r'^(\d{4})-', f)] if m]
        print('%04d' % (max(nums) + 1 if nums else 1))
        return 0
    if kind == 'q':
        if not a.run:
            raise Fail('id next q needs --run <slug>')
        print('Q%d' % next_q(a.run))
        return 0
    if not a.doc:
        raise Fail('id next %s needs --doc <path>' % kind)
    text = read(a.doc)
    if kind in ('fr', 'nfr'):
        pref = kind.upper()
        nums = [int(n) for n in re.findall(r'(?<![A-Z])%s-(\d+)\b' % pref, text)]
        print('%s-%03d' % (pref, max(nums) + 1 if nums else 1))
        return 0
    found = re.findall(r'\bUS-([A-Z0-9]+)-(\d+)\b', text)
    key = a.key or (found[0][0] if found else None)
    if not key:
        raise Fail('no US-<KEY>-NNN ids in %s; pass --key' % a.doc)
    nums = [int(n) for k, n in found if k == key]
    print('US-%s-%03d' % (key, max(nums) + 1 if nums else 1))
    return 0


# ================================================================================= clarifications

CLAR_HEAD = re.compile(r'^## Q(\d+) · (\S+) · asked by (.+?) \((.*)\) · owner: (\S+)\s*$', re.M)


def clar_path(slug):
    return run_dir(slug) + '/clarifications.md'


def next_q(slug):
    p = os.path.join(root(), clar_path(slug))
    text = open(p, encoding='utf-8').read() if os.path.exists(p) else ''
    nums = [int(m.group(1)) for m in CLAR_HEAD.finditer(text)]
    return max(nums) + 1 if nums else 1


def cmd_clar_add(a):
    path = clar_path(a.slug)
    full = os.path.join(root(), path)
    text = open(full, encoding='utf-8').read() if os.path.exists(full) else '# Clarifications: %s\n' % a.slug
    n = next_q(a.slug)
    entry = '\n## Q%d · %s · asked by %s (%s) · owner: %s\n**Q:** %s\n**A:** %s\n**Recorded in:** %s\n' % (
        n, today(), a.asked_by, a.wp, a.owner, ' '.join(a.q.split()), ' '.join(a.a.split()),
        ' '.join(a.recorded_in.split()))
    write(path, text.rstrip('\n') + '\n' + entry)
    print('Q%d → %s' % (n, path))
    return 0


def cmd_clar_count(a):
    p = os.path.join(root(), clar_path(a.slug))
    text = open(p, encoding='utf-8').read() if os.path.exists(p) else ''
    n = sum(1 for m in CLAR_HEAD.finditer(text)
            if m.group(4).strip() == a.wp and (not a.asked_by or m.group(3).strip() == a.asked_by))
    total = n + a.adding
    over = total > CLAR_BUDGET
    print('clarifications: %d/%d for %s%s%s' % (n, CLAR_BUDGET, a.wp, ' (+%d → %d)' % (a.adding, total) if a.adding else '',
                                                 ' · over budget: return STATUS: under-specified' if over else ''))
    return 1 if over else 0


# ================================================================================== traceability

REQ = re.compile(r'(?<![A-Za-z])(N?FR)-(\d+)\b')
STRUCK = re.compile(r'~~\s*(N?FR-\d+)\s*~~')


def prd_ids(text):
    """({defined live ids}, {struck ids}, [duplicate ids]) from the requirement bullets of a PRD."""
    live, struck, seen, dups = set(), set(), set(), []
    for line in text.splitlines():
        # `- **FR-001** — …` is live; `- ~~FR-007~~ (removed …)`, `- ~~**FR-007**~~`, `- **~~FR-007~~**` are retired.
        m = re.match(r'^\s*[-*]\s+((?:\*\*|~~)+)\s*(N?FR-\d+)\b', line)
        if not m:
            continue
        rid = m.group(2)
        if rid in seen:
            dups.append(rid)
        seen.add(rid)
        (struck if '~~' in m.group(1) else live).add(rid)
    return live, struck, dups


def story_sections(text):
    lines = text.splitlines()
    out = {}
    for m, s, e in sections(lines, r'(US-[A-Z0-9]+-\d+)\b', 2):
        body = '\n'.join(lines[s:e])
        out.setdefault(m.group(1), []).append(body)
    return out


def story_field(body, name):
    m = re.search(r'^\s*[-*]\s+\*\*%s:\*\*\s*(.*?)(?:\s*<!--.*)?$' % re.escape(name), body, re.M)
    return m.group(1).strip() if m else ''


def cmd_trace_prd(a):
    d = a.prd_dir.rstrip('/')
    prd_p, st_p = d + '/prd.md', d + '/stories.md'
    prd, stories = read(prd_p), read(st_p)
    live, struck, dups = prd_ids(prd)
    issues = ['duplicate requirement id %s in prd.md' % r for r in dups]
    secs = story_sections(stories)
    issues += ['duplicate story section %s' % s for s, b in secs.items() if len(b) > 1]
    try:
        t = table_under(stories.splitlines(), r'^User stories\b')
    except Fail:
        t = None
    lines = stories.splitlines()
    if t is None:
        for idx in range(len(lines)):
            if lines[idx].lstrip().startswith('|'):
                t = Table(lines, idx, len(lines))
                break
    table_ids = set()
    if t is not None:
        ic = t.col('ID')
        table_ids = {cells[ic] for _, cells in t.rows() if re.match(r'^US-[A-Z0-9]+-\d+$', cells[ic])}
    issues += ['%s in the story table but has no section' % s for s in sorted(table_ids - set(secs))]
    issues += ['%s has a section but is not in the story table' % s for s in sorted(set(secs) - table_ids)]
    ready = 0
    for sid, bodies in sorted(secs.items()):
        body = bodies[0]
        status = story_field(body, 'Status').split()[0] if story_field(body, 'Status') else ''
        if status == 'dropped':
            continue
        ready += status == 'ready'
        if not re.search(r'\*\*AC\d+\*\*', body):
            issues.append('%s has no acceptance criteria' % sid)
        refs = ['%s-%s' % m for m in REQ.findall(story_field(body, 'Requirements'))]
        if not refs:
            issues.append('%s links no FR/NFR' % sid)
        for r in refs:
            if r in struck:
                issues.append('%s links removed %s' % (sid, r))
            elif r not in live:
                issues.append('%s links unknown %s' % (sid, r))
    if a.base:
        verify_base(a.base)
        old_prd, old_st = git_show(a.base, rel(prd_p)), git_show(a.base, rel(st_p))
        if old_prd:
            ol, os_, _ = prd_ids(old_prd)
            for r in sorted((ol | os_) - live - struck):
                issues.append('%s existed at BASE and is gone without ~~strike-through~~ (renumbered?)' % r)
        if old_st:
            for s in sorted(set(story_sections(old_st)) - set(secs)):
                issues.append('%s existed at BASE and is gone (mark it dropped instead)' % s)
    fr = sum(1 for r in live if r.startswith('FR'))
    print('PRD: %s · FR %d · NFR %d · removed %d · stories %d (%d ready) · issues %d' % (
        prd_p, fr, len(live) - fr, len(struck), len(secs), ready, len(issues)))
    for i in issues[:20]:
        print('  ' + i)
    if len(issues) > 20:
        print('  … %d more' % (len(issues) - 20))
    return 1 if issues else 0


def expand_ids(cell):
    """FR/NFR ids in a cell, expanding ranges such as FR-001–FR-003."""
    out = set()
    for m in re.finditer(r'(N?FR)-(\d+)(?:\s*[–—-]\s*(?:(N?FR)-)?(\d+))?', cell):
        p, a_ = m.group(1), int(m.group(2))
        b = int(m.group(4)) if m.group(4) and (m.group(3) in (None, p)) else a_
        width = len(m.group(2))
        for n in range(a_, max(a_, b) + 1):
            out.add('%s-%0*d' % (p, width, n))
    return out


def cmd_trace_hld(a):
    live, struck, _ = prd_ids(read(a.prd))
    lines = read(a.hld).splitlines()
    t = table_under(lines, r'^(\d+\.\s*)?Traceability$')
    traced = set()
    for _, cells in t.rows():
        traced |= expand_ids(cells[0])
    missing = sorted(live - traced)
    unknown = sorted(traced - live - struck)
    removed = sorted(traced & struck)
    print('HLD: %s · traced %d/%d%s%s%s' % (
        a.hld, len(live & traced), len(live), ' · missing: ' + ' '.join(missing) if missing else '',
        ' · unknown ids: ' + ' '.join(unknown) if unknown else '',
        ' · traces removed: ' + ' '.join(removed) if removed else ''))
    return 1 if missing or unknown else 0


def cmd_trace_plan(a):
    musts = set()
    for sp in a.stories:
        for sid, bodies in story_sections(read(sp)).items():
            body = bodies[0]
            pr = (story_field(body, 'Priority').split() or [''])[0]
            st = (story_field(body, 'Status').split() or [''])[0]
            if pr == 'must' and st != 'dropped':
                musts.add(sid)
    _, lines, phases = load_plan(a.plan)
    t = phase_map(lines)
    pc, sc = t.col('Phase'), t.col('Stories')
    placed = {}
    for _, cells in t.rows():
        for sid in re.findall(r'US-[A-Z0-9]+-\d+', cells[sc]):
            placed.setdefault(sid, []).append(cells[pc])
    unplaced = sorted(musts - set(placed))
    multi = sorted('%s in %s' % (s, ' '.join(p)) for s, p in placed.items() if s in musts and len(p) > 1)
    bad_tasks = []
    for pid, (s, e) in phases.items():
        for i, tid, _ in phase_tasks(lines, s, e):
            missing = [k for k in ('files:', 'satisfies:') if k not in lines[i]]
            if missing:
                bad_tasks.append('%s %s lacks %s' % (pid, tid, ' and '.join(k[:-1] for k in missing)))
    print('COVERAGE: %d/%d must-stories placed; unplaced: %s' % (
        len(musts) - len(unplaced), len(musts), ' '.join(unplaced) or 'none'))
    if multi:
        print('IN MORE THAN ONE PHASE: %s' % '; '.join(multi))
    if bad_tasks:
        print('TASKS: %d incomplete' % len(bad_tasks))
        for b in bad_tasks[:15]:
            print('  ' + b)
    return 1 if unplaced or multi or bad_tasks else 0


# ============================================================================================= qa

DEFAULT_TEST_GLOBS = ['test_*.py', '*_test.py', '*_test.go', '*.test.*', '*.spec.*', '*Test.java', '*Tests.java',
                      '*Test.kt', '*Tests.cs', '*Test.cs', 'tests/*', 'test/*', '__tests__/*', '*/tests/*',
                      '*/test/*', '*/__tests__/*', '*.Tests/*', '*/*.Tests/*', 'conftest.py', '*/conftest.py']


def is_test(path):
    globs = cfg()['gates'].get('test_globs') or DEFAULT_TEST_GLOBS
    if isinstance(globs, str):
        globs = [globs]
    name = path.rsplit('/', 1)[-1]
    return any(fnmatch.fnmatch(path, g) or fnmatch.fnmatch(name, g) for g in globs)


def cmd_qa_changed(a):
    files = changed_files(a.base)
    if a.under:
        files = [(s, p) for s, p in files if under(p, *[u.rstrip('/') for u in a.under])]
    untracked = sum(1 for s, _ in files if s == '?')
    if a.json:
        out = [{'status': s, 'path': p} for s, p in files]
        if a.lines:
            for o in out:
                o['lines'] = ranges(changed_lines(a.base, o['path'], o['status'])) if o['status'] != 'D' else ''
        print(json.dumps(out))
        return 0
    print('changed: %d files (%d untracked) since %s' % (len(files), untracked, a.base))
    for s, p in files:
        extra = ''
        if a.lines and s != 'D':
            extra = ' ' + (ranges(changed_lines(a.base, p, s)) or '-')
        print('%s %s%s' % (s, p, extra))
    return 0


# ---------------------------------------------------------------------- coverage reports

REPORT_NAMES = {'lcov.info': 'lcov', 'coverage.xml': 'cobertura', 'cobertura.xml': 'cobertura',
                'cobertura-coverage.xml': 'cobertura', 'coverage.cobertura.xml': 'cobertura',
                'coverage.json': 'json', 'coverage-final.json': 'json'}
SKIP_DIRS = {'.git', 'node_modules', '.venv', 'venv', '.tox', '.mypy_cache', '__pycache__', '.sw-factory', '.claude'}


def find_reports():
    found = []
    for dirpath, dirnames, filenames in os.walk(root()):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for f in filenames:
            if f in REPORT_NAMES:
                p = os.path.join(dirpath, f)
                found.append((os.path.getmtime(p), p, REPORT_NAMES[f]))
    return sorted(found, reverse=True)


def norm_report_path(p):
    p = p.replace('\\', '/')
    if os.path.isabs(p):
        return rel(p)
    return os.path.normpath(p).replace(os.sep, '/')


def parse_lcov(text):
    data, cur = {}, None
    for line in text.splitlines():
        if line.startswith('SF:'):
            cur = data.setdefault(norm_report_path(line[3:].strip()), {})
        elif line.startswith('DA:') and cur is not None:
            parts = line[3:].split(',')
            ln, hits = int(parts[0]), int(float(parts[1]))
            cur[ln] = max(cur.get(ln, 0), hits)
        elif line.startswith('end_of_record'):
            cur = None
    return data


def parse_cobertura(text):
    tree = ET.fromstring(text)
    sources = [s.text.strip() for s in tree.iter('source') if s.text and s.text.strip()]
    data = {}
    for cls in tree.iter('class'):
        fn = cls.get('filename') or ''
        path = fn
        for src in sources:
            cand = os.path.join(src, fn)
            if os.path.exists(cand if os.path.isabs(cand) else os.path.join(root(), cand)):
                path = cand
                break
        lines = data.setdefault(norm_report_path(path), {})
        for ln in cls.iter('line'):
            n, hits = int(ln.get('number')), int(float(ln.get('hits', '0')))
            lines[n] = max(lines.get(n, 0), hits)
    return data


def parse_json_cov(text):
    d = json.loads(text)
    data = {}
    if isinstance(d, dict) and isinstance(d.get('files'), dict):  # coverage.py
        for path, f in d['files'].items():
            lines = data.setdefault(norm_report_path(path), {})
            for n in f.get('executed_lines', []):
                lines[n] = 1
            for n in f.get('missing_lines', []):
                lines.setdefault(n, 0)
        return data
    if isinstance(d, dict) and d and all(isinstance(v, dict) and 'statementMap' in v for v in d.values()):  # istanbul
        for path, f in d.items():
            lines = data.setdefault(norm_report_path(f.get('path') or path), {})
            for sid, loc in f['statementMap'].items():
                n = loc['start']['line']
                lines[n] = max(lines.get(n, 0), int(f['s'].get(sid, 0)))
        return data
    raise Fail('unrecognised JSON coverage format (expected coverage.py JSON or istanbul coverage-final.json)', 3)


PARSERS = {'lcov': parse_lcov, 'cobertura': parse_cobertura, 'json': parse_json_cov}


def load_report(path, fmt):
    if not fmt:
        fmt = REPORT_NAMES.get(os.path.basename(path))
        if not fmt:
            fmt = 'lcov' if path.endswith('.info') else 'cobertura' if path.endswith('.xml') else \
                'json' if path.endswith('.json') else None
    if fmt not in PARSERS:
        raise Fail('cannot tell the format of %s; pass --format lcov|cobertura|json' % path, 3)
    try:
        with open(path, encoding='utf-8') as f:
            return fmt, PARSERS[fmt](f.read())
    except Fail:
        raise
    except (OSError, ValueError, ET.ParseError, KeyError, TypeError) as e:
        raise Fail('cannot parse %s as %s: %s' % (path, fmt, e), 3)


def match_report(path, keys):
    if path in keys:
        return path
    hits = [k for k in keys if k.endswith('/' + path) or path.endswith('/' + k)]
    return hits[0] if len(hits) == 1 else None


def executable_guess(path):
    """Lines of a source file missing from the report: non-blank lines that are not comments."""
    try:
        with open(os.path.join(root(), path), encoding='utf-8', errors='replace') as f:
            return {i for i, t in enumerate(f, 1)
                    if t.strip() and not re.match(r'^\s*(#|//|/\*|\*|--|;|"""|\'\'\')', t)}
    except OSError:
        return set()


def cmd_qa_coverage(a):
    g = cfg()['gates']
    scope = a.scope or g.get('coverage_scope', 'changed')
    minimum = float(a.min if a.min is not None else g.get('coverage_min', 90))
    if a.report:
        report = a.report if os.path.isabs(a.report) else os.path.join(root(), a.report)
        if not os.path.exists(report):
            print('GATE UNMEASURABLE: report not found: %s' % a.report)
            return 3
    else:
        found = find_reports()
        if not found:
            print('GATE UNMEASURABLE: no coverage report found (looked for %s); run the coverage command or pass '
                  '--report' % ', '.join(sorted(REPORT_NAMES)))
            return 3
        report = found[0][1]
    try:
        fmt, data = load_report(report, a.format)
    except Fail as e:
        print('GATE UNMEASURABLE: %s' % e)
        return 3
    rr = rel(report)
    if not data:
        print('GATE UNMEASURABLE: %s (%s) has no line data' % (rr, fmt))
        return 3
    if scope == 'overall':
        total = sum(len(v) for v in data.values())
        cov = sum(1 for v in data.values() for h in v.values() if h > 0)
        pct = 100.0 * cov / total if total else 100.0
        print('report: %s (%s)' % (rr, fmt))
        print('coverage overall %.1f%% (%d/%d lines, %d files) min %g → %s' % (
            pct, cov, total, len(data), minimum, 'PASS' if pct >= minimum else 'FAIL'))
        return 0 if pct >= minimum else 1
    if not a.base:
        raise Fail('coverage scope "changed" needs --base <ref>')
    keys = set(data)
    exts = {os.path.splitext(k)[1] for k in keys if os.path.splitext(k)[1]}
    rmtime = os.path.getmtime(report)
    per_file, not_in_report, stale = [], [], []
    for st, path in changed_files(a.base):
        if st == 'D' or is_test(path) or not os.path.isfile(os.path.join(root(), path)):
            continue
        key = match_report(path, keys)
        if key is None and os.path.splitext(path)[1] not in exts:
            continue  # not a language this report instruments (docs, config, …)
        if os.path.getmtime(os.path.join(root(), path)) > rmtime + 1:
            stale.append(path)
        lines = changed_lines(a.base, path, st)
        if key is None:
            ex = lines & executable_guess(path)
            if ex:
                not_in_report.append((path, len(ex)))
                per_file.append((path, 0, len(ex), ex))
            continue
        ex = lines & set(data[key])
        if not ex:
            continue
        unc = {n for n in ex if data[key][n] <= 0}
        per_file.append((path, len(ex) - len(unc), len(ex), unc))
    if stale:
        print('GATE UNMEASURABLE: %s is older than changed sources (%s); rerun the coverage command' % (
            rr, ', '.join(stale[:3]) + (', …' if len(stale) > 3 else '')))
        return 3
    total = sum(f[2] for f in per_file)
    cov = sum(f[1] for f in per_file)
    print('report: %s (%s)' % (rr, fmt))
    if total == 0:
        print('coverage changed n/a (no executable lines changed outside tests) min %g → PASS' % minimum)
        return 0
    pct = 100.0 * cov / total
    ok = pct >= minimum
    print('coverage changed %.1f%% (%d/%d lines, %d files) min %g → %s' % (
        pct, cov, total, len(per_file), minimum, 'PASS' if ok else 'FAIL'))
    worst = sorted((f for f in per_file if f[1] < f[2]), key=lambda f: f[1] / f[2])
    for path, c, t, unc in worst[:10]:
        print('  %s %.1f%% (%d/%d) uncovered %s' % (path, 100.0 * c / t, c, t, ranges(unc)))
    if len(worst) > 10:
        print('  … %d more files with uncovered lines' % (len(worst) - 10))
    if not_in_report:
        print('not in report (counted as 0%%): %s' % ', '.join('%s (%d lines)' % x for x in not_in_report))
    return 0 if ok else 1


def tick_only(base, path):
    removed, added = [], []
    for line in git('diff', '-U0', '--no-renames', base, '--', path).splitlines():
        if line.startswith(('---', '+++')):
            continue
        if line.startswith('-'):
            removed.append(line[1:])
        elif line.startswith('+'):
            added.append(line[1:])
    if not removed or len(removed) != len(added):
        return False
    return all(re.sub(r'^(\s*[-*]\s+\[) \]', r'\1x]', r) == ad and r != ad for r, ad in zip(removed, added))


def cmd_qa_drift(a):
    lpath = ledger_path(a.slug)
    if not os.path.exists(os.path.join(root(), lpath)):
        raise Fail('no ledger for run %s (%s)' % (a.slug, lpath))
    llines = read(lpath).splitlines()
    accounted = []
    for name, col in (('Documents', 'Path'), ('Log', 'Artifact')):
        try:
            t = table_under(llines, r'^%s$' % name)
            c = t.col(col)
            accounted += [cells[c] for _, cells in t.rows()]
        except Fail:
            pass
    cp = os.path.join(root(), clar_path(a.slug))
    if os.path.exists(cp):
        accounted += re.findall(r'^\*\*Recorded in:\*\*\s*(.*)$', open(cp, encoding='utf-8').read(), re.M)
    blob = '\n'.join(accounted)

    def is_accounted(path):
        return re.search(r'(?<![\w./-])%s(?![\w/-]|\.\w)' % re.escape(path), blob) is not None

    doc_roots = doc_dirs()
    drift, ok = [], 0
    for st, path in changed_files(a.base):
        if path == '.sw-factory/config.yaml' or under(path, '.claude'):
            drift.append('%s — gates or guards altered' % path)
        elif under(path, *doc_roots):
            if is_accounted(path):
                ok += 1
            elif under(path, P('plans')) and st == 'M' and tick_only(a.base, path):
                ok += 1
            else:
                drift.append('%s — not in the ledger or the clarification log' % path)
    if drift:
        print('DRIFT: %d (DOC DRIFT)' % len(drift))
        for d in drift:
            print('  ' + d)
        print('accounted: %d' % ok)
        return 1
    print('DRIFT: none (%d document changes accounted)' % ok)
    return 0


SKIP_PATTERNS = [
    r'\b(?:it|test|describe|context)\.skip\s*\(', r'\b(?:it|test|describe)\.only\s*\(', r'\bx(?:it|describe|test)\s*\(',
    r'\b(?:it|test)\.todo\s*\(', r'@pytest\.mark\.(?:skip|skipif|xfail)\b', r'\bpytest\.skip\s*\(',
    r'@unittest\.skip', r'\bself\.skipTest\s*\(', r'\bt\.Skip(?:Now|f)?\s*\(', r'\[Ignore\b',
    r'\[(?:Fact|Theory)\s*\([^)]*\bSkip\s*=', r'@Disabled\b', r'@Ignore\b', r'#\[ignore\]', r'\bskip\s*:\s*true\b',
]
EXCLUDE_PATTERNS = [
    r'pragma:\s*no\s*cover', r'\b(?:istanbul|c8|v8)\s+ignore\b', r'ExcludeFromCodeCoverage', r':nocov:',
    r'LCOV_EXCL', r'@codeCoverageIgnore', r'coverage:\s*ignore',
]
COV_CONFIG = ['.coveragerc', 'setup.cfg', 'pyproject.toml', 'tox.ini', 'jest.config.*', 'vitest.config.*',
              'vite.config.*', '.nycrc*', '.c8rc*', 'codecov.yml', '.codecov.yml', '*.runsettings', 'package.json',
              'karma.conf.*', 'build.gradle*', 'pom.xml', 'Directory.Build.props']
COV_CONFIG_LINE = re.compile(r'\b(?:omit|exclude|excludes|ignore|coveragePathIgnorePatterns|collectCoverageFrom|'
                             r'ExcludeByFile|ExcludeByAttribute|fail_under|coverageThreshold|thresholds?)\b', re.I)


def cmd_qa_weakening(a):
    skip = re.compile('|'.join(SKIP_PATTERNS))
    excl = re.compile('|'.join(EXCLUDE_PATTERNS), re.I)
    found = []
    for st, path in changed_files(a.base):
        if st == 'D' or path.endswith('.md') or under(path, '.claude', *doc_dirs()):
            continue
        name = path.rsplit('/', 1)[-1]
        conf = any(fnmatch.fnmatch(name, g) for g in COV_CONFIG)
        for n, text in added_lines(a.base, path, st):
            kind = 'skip' if skip.search(text) else 'exclusion' if excl.search(text) else \
                'coverage-config' if conf and COV_CONFIG_LINE.search(text) else None
            if kind:
                t = text.strip()
                found.append((kind, '%s:%d' % (path, n), t if len(t) <= 90 else t[:87] + '…'))
    if not found:
        print('weakening: none')
        return 0
    counts = {}
    for k, _, _ in found:
        counts[k] = counts.get(k, 0) + 1
    print('weakening: %d (%s) · each needs a design justification, otherwise it is a finding' % (
        len(found), ', '.join('%d %s' % (v, k) for k, v in sorted(counts.items()))))
    for k, where, t in found[:30]:
        print('  %-15s %s  %s' % (k, where, t))
    if len(found) > 30:
        print('  … %d more' % (len(found) - 30))
    return 1


# ========================================================================================== level

R_VALUES = ('none', 'clarify', 'extend', 'new')
D_VALUES = ('none', 'local', 'cross', 'new')
K_FLAGS = ('data-migration', 'security', 'breaking-api', 'irreversible', 'regulatory', 'money', 'perf-critical')
TRACK_FOR = {0: 'direct', 1: 'subagents', 2: 'opsx-loop', 3: 'openspec'}
FALLBACK = {2: ('subagents', 'add the plan gate and a human checkpoint after QA; loses the delta specs that keep '
                             'openspec/specs/ in sync'),
            3: ('subagents', 'add a human checkpoint after every phase; loses the delta specs and the supervised '
                             'spec checkpoints')}


def parse_tracks(line):
    line = line.split('TRACKS:', 1)[-1]
    return {k: v for k, _, v in (t.partition('=') for t in line.split()) if k}


def cmd_level(a):
    sig = {}
    for tok in a.signals:
        k, sep, v = tok.partition('=')
        if not sep:
            raise Fail('expected SIGNAL=value, got %r' % tok)
        sig[k.strip().upper()] = v.strip().lower()
    missing = [k for k in ('R', 'D', 'K', 'S', 'G') if k not in sig]
    if missing:
        raise Fail('missing signals: %s (need R= D= K= S= G=)' % ' '.join(missing))
    r, d, g = sig['R'], sig['D'], sig['G']
    if r not in R_VALUES:
        raise Fail('R must be one of %s' % '|'.join(R_VALUES))
    if d not in D_VALUES:
        raise Fail('D must be one of %s' % '|'.join(D_VALUES))
    if g not in ('yes', 'no'):
        raise Fail('G must be yes|no')
    flags = [] if sig['K'] in ('none', '', '-') else [f.strip() for f in sig['K'].split(',') if f.strip()]
    bad = [f for f in flags if f not in K_FLAGS]
    if bad:
        raise Fail('unknown K flags: %s (known: %s)' % (', '.join(bad), ', '.join(K_FLAGS)))
    m = re.match(r'^~?(\d+)$', sig['S'])
    if not m:
        raise Fail('S must be a file count, e.g. S=8 (components go in C=<n>)')
    files = int(m.group(1))
    comps = int(sig['C']) if sig.get('C', '').isdigit() else 1
    notes = []
    if r == 'extend':
        if a.stories is None:
            notes.append('R=extend without --stories: assumed > 2 stories')
        rf = 1 if a.stories is not None and a.stories <= 2 else 2
    else:
        rf = {'none': 0, 'clarify': 0, 'new': 2}[r]
    df = {'none': 0, 'local': 1, 'cross': 2, 'new': 2}[d]
    if d == 'cross' and (files > 15 or comps > 3):
        df = 3
    kf = max([3 if f != 'perf-critical' else 2 for f in flags] or [0])
    sf = 0 if files <= 3 and comps <= 3 else 1 if files <= 15 and comps <= 3 else 2
    gf = 2 if g == 'yes' else 0
    floors = {'R': (rf, 'R=' + r), 'D': (df, 'D=' + d), 'K': (kf, 'K=' + ','.join(flags or ['none'])),
              'S': (sf, 'S=%d' % files + ('/C=%d' % comps if 'C' in sig else '')), 'G': (gf, 'G=' + g)}
    level = max(f for f, _ in floors.values())
    deciding = [label for f, label in floors.values() if f == level and level > 0] or ['all signals at L0']
    track, fallback_note = TRACK_FOR[level], ''
    if a.tracks:
        avail = parse_tracks(a.tracks)
        if avail.get(track) != 'yes':
            fb = FALLBACK.get(level)
            if fb and avail.get(fb[0]) == 'yes':
                fallback_note = '%s unavailable (%s) → fallback %s: %s' % (track, avail.get(track, 'unknown'), fb[0],
                                                                         fb[1])
                track = fb[0]
            else:
                print('LEVEL: L%d · deciding: %s' % (level, ', '.join(deciding)))
                print('TRACK: none available (%s is %s, no usable fallback) · ask the human' % (
                    track, avail.get(track, 'unknown')))
                return 1
    adrs = [f for f in flags if f != 'perf-critical']
    prefix = a.phase.upper() + ' · ' if a.phase else ''
    print('LEVEL: L%d · deciding: %s' % (level, ', '.join(deciding)))
    print('TRACK: %s' % track)
    if fallback_note:
        print('FALLBACK: %s' % fallback_note)
    print('ADR REQUIRED: %s' % ('accepted ADR per flag before implementation: ' + ', '.join(adrs) if adrs else 'none'))
    for n in notes:
        print('NOTE: %s' % n)
    print('LEDGER: %sL%d · %s · %s' % (prefix, level, track, deciding[0]))
    return 0


# ========================================================================================== gates

COUNTERS = [
    ('pytest', re.compile(r'^=+ (.*\b(?:passed|failed|error|errors|no tests ran)\b.*) in [\d.]+s', re.M),
     lambda m: {k: int(n) for n, k in re.findall(r'(\d+) (passed|failed|errors?|skipped|xfailed|xpassed)', m.group(1))}),
    ('jest', re.compile(r'^Tests:\s+(.*\d+ total)', re.M),
     lambda m: {k: int(n) for n, k in re.findall(r'(\d+) (passed|failed|skipped|todo|total)', m.group(1))}),
    ('vitest', re.compile(r'^\s*Tests\s+(.*\(\d+\))', re.M),
     lambda m: {k: int(n) for n, k in re.findall(r'(\d+) (passed|failed|skipped|todo)', m.group(1))}),
    ('dotnet', re.compile(r'(?:Passed|Failed)!\s+-\s+Failed:\s+(\d+),\s+Passed:\s+(\d+),\s+Skipped:\s+(\d+)'),
     lambda m: {'failed': int(m.group(1)), 'passed': int(m.group(2)), 'skipped': int(m.group(3))}),
    ('dotnet', re.compile(r'total:\s*(\d+),\s*failed:\s*(\d+),\s*succeeded:\s*(\d+),\s*skipped:\s*(\d+)', re.I),
     lambda m: {'failed': int(m.group(2)), 'passed': int(m.group(3)), 'skipped': int(m.group(4))}),
    ('mocha', re.compile(r'^\s*(\d+) passing', re.M),
     lambda m: {'passed': int(m.group(1))}),
]


def count_tests(log):
    for name, rx, fn in COUNTERS:
        ms = list(rx.finditer(log))
        if ms:
            c = fn(ms[-1])
            if 'errors' in c:
                c['error'] = c.pop('errors')
            if name == 'mocha':
                f = re.findall(r'^\s*(\d+) failing', log, re.M)
                c['failed'] = int(f[-1]) if f else 0
            return name, c
    gp = len(re.findall(r'^ok\s+\S+', log, re.M))
    gf = len(re.findall(r'^FAIL\s+\S+', log, re.M))
    if gp or gf:
        return 'go test', {'packages ok': gp, 'packages failed': gf}
    return None, {}


def cmd_gates_run(a):
    gates = ['build', 'test', 'coverage', 'lint'] if a.gate == 'all' else [a.gate]
    if a.cmd and a.gate == 'all':
        raise Fail('--cmd overrides one gate; name the gate instead of "all"')
    commands = cfg()['commands']
    logdir = run_dir(a.run) + '/logs'
    label = a.label or datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    os.makedirs(os.path.join(root(), logdir), exist_ok=True)
    failed = unconfigured = False
    for gate in gates:
        cmd = a.cmd or commands.get(gate) or ''
        if not cmd:
            if a.gate == 'all' and gate == 'lint':
                continue
            print('%s: not configured in .sw-factory/config.yaml — discover the command and pass --cmd' % gate)
            unconfigured = True
            continue
        log = '%s/%s-%s.log' % (logdir, label, gate)
        with open(os.path.join(root(), log), 'w', encoding='utf-8') as out:
            out.write('$ %s\n' % cmd)
            out.flush()
            try:
                rc = subprocess.run(cmd, shell=True, cwd=root(), stdout=out, stderr=subprocess.STDOUT,
                                    timeout=a.timeout).returncode
            except subprocess.TimeoutExpired:
                rc = 124
                out.write('\nsf: timed out after %ss\n' % a.timeout)
        text = open(os.path.join(root(), log), encoding='utf-8', errors='replace').read()
        counts_s = ''
        ok = rc == 0
        if gate == 'test':
            tool, c = count_tests(text)
            if tool:
                counts_s = ' · ' + ', '.join('%d %s' % (v, k) for k, v in c.items()) + ' (%s)' % tool
                bad = c.get('failed', 0) + c.get('error', 0) + c.get('packages failed', 0)
                passed = c.get('passed', 0)
                need = float(cfg()['gates'].get('tests_passing', 100))
                if bad or (passed + bad and 100.0 * passed / (passed + bad) < need):
                    ok = False
            else:
                counts_s = ' · counts: not parsed, see log'
        failed |= not ok
        print('%s %s exit %d%s · log: %s' % (gate, '✅' if ok else '❌', rc, counts_s, log))
        if not ok:
            tail = text.rstrip('\n').splitlines()[-a.tail:]
            for line in tail:
                print('    ' + line[:200])
    return 1 if failed else 2 if unconfigured else 0


# =========================================================================================== main

def build_parser():
    p = argparse.ArgumentParser(prog='swf-cli.py', description='sw-factory bookkeeping. Exit: 0 ok · 1 problems found · '
                                                          '2 usage/input error · 3 unmeasurable.')
    p.add_argument('--version', action='version', version='swf-cli ' + VERSION)
    sub = p.add_subparsers(dest='group', metavar='<group>')
    sub.required = True

    def group(name, help_):
        g = sub.add_parser(name, help=help_).add_subparsers(dest='cmd', metavar='<command>')
        g.required = True
        return g

    def cmd(g, name, fn, help_):
        c = g.add_parser(name, help=help_, description=help_)
        c.set_defaults(fn=fn)
        return c

    g = group('plan', 'plan tasks and phase status')
    c = cmd(g, 'status', cmd_plan_status, 'ticked/total tasks per phase, and the open task ids')
    c.add_argument('plan')
    c.add_argument('--phase')
    c = cmd(g, 'tick', cmd_plan_tick, 'tick tasks in a phase (changes nothing else)')
    c.add_argument('plan')
    c.add_argument('phase')
    c.add_argument('tasks', nargs='+')
    c = cmd(g, 'phases', cmd_plan_phases, 'the Phase map as one line per phase')
    c.add_argument('plan')
    c = cmd(g, 'sync', cmd_plan_sync, 'sync the Phase map Status column and front-matter status from the ledger')
    c.add_argument('plan')
    c.add_argument('--ledger', required=True)

    g = group('ledger', 'the run ledger (<runs>/<slug>/ledger.md)')
    c = cmd(g, 'init', cmd_ledger_init, 'create the ledger from the template with base ref, branch and TRACKS')
    c.add_argument('slug')
    c.add_argument('--request', required=True)
    c.add_argument('--entry', required=True,
                   choices=['idea', 'change', 'defect', 'prd-only', 'design-only', 'plan-only', 'execute'])
    c.add_argument('--tracks', help='the preflight TRACKS line (default: run the preflight)')
    c = cmd(g, 'set', cmd_ledger_set, 'set a header field: ' + ', '.join(HEADER_FIELDS))
    c.add_argument('slug')
    c.add_argument('field')
    c.add_argument('value')
    c = cmd(g, 'frame', cmd_ledger_frame, 'set the Frame lines')
    c.add_argument('slug')
    c.add_argument('--problem')
    c.add_argument('--goals')
    c.add_argument('--context')
    c = cmd(g, 'log', cmd_ledger_log, 'append a numbered Log row')
    c.add_argument('slug')
    c.add_argument('--stage', required=True)
    c.add_argument('--agent', required=True)
    c.add_argument('--agent-id', help='id the spawn returned, used to resume the agent later')
    c.add_argument('--status', required=True)
    c.add_argument('--artifact')
    c.add_argument('--notes')
    c = cmd(g, 'doc', cmd_ledger_doc, 'add or update Documents rows; version and status come from front matter')
    c.add_argument('slug')
    c.add_argument('paths', nargs='+')
    c.add_argument('--written-by', required=True)
    c.add_argument('--kind')
    c = cmd(g, 'phase', cmd_ledger_phase, 'add or update a Phases row; --retry spends one QA retry round')
    c.add_argument('slug')
    c.add_argument('phase')
    c.add_argument('--level')
    c.add_argument('--track')
    c.add_argument('--status', choices=['todo', 'in-progress', 'blocked', 'done'])
    c.add_argument('--base')
    c.add_argument('--notes')
    c.add_argument('--retry', action='store_true', help='QA returned BLOCKING: spend a retry round (exit 1 if none left)')
    c = cmd(g, 'decision', cmd_ledger_decision, 'append a Human decisions row')
    c.add_argument('slug')
    c.add_argument('--gate', required=True)
    c.add_argument('--decision', required=True)
    c.add_argument('--recorded-in')
    c = cmd(g, 'summary', cmd_ledger_summary, 'the ledger in ≤ 15 lines (status, resume, after compaction)')
    c.add_argument('slug')

    g = group('doc', 'document front matter, versions, changelogs, decision logs')
    c = cmd(g, 'meta', cmd_doc_meta, 'front-matter fields of documents (default: id status version approvals)')
    c.add_argument('paths', nargs='+')
    c.add_argument('--field', action='append')
    c = cmd(g, 'set', cmd_doc_set, 'set front-matter keys, keeping comments')
    c.add_argument('path')
    c.add_argument('pairs', nargs='+', metavar='key=value')
    c = cmd(g, 'bump', cmd_doc_bump, 'bump the version and add a dated Changelog row')
    c.add_argument('path')
    c.add_argument('part', choices=['major', 'minor', 'patch'])
    c.add_argument('--change', required=True)
    c.add_argument('--trigger', help='the Reason/Trigger column')
    c.add_argument('--set', action='append', metavar='key=value', help='also set a front-matter key')
    c.add_argument('--date')
    c = cmd(g, 'decide', cmd_doc_decide, 'add a Decision log row')
    c.add_argument('path')
    c.add_argument('--decision', required=True)
    c.add_argument('--by', required=True)
    c.add_argument('--source', required=True)
    c.add_argument('--date')
    c = cmd(g, 'versions', cmd_doc_versions, 'documents changed since a ref, with their version change')
    c.add_argument('--since', required=True)

    g = group('id', 'next free ids')
    c = cmd(g, 'next', cmd_id_next, 'next ADR number, FR/NFR/US id, or clarification Q number')
    c.add_argument('kind', choices=['adr', 'fr', 'nfr', 'us', 'q'])
    c.add_argument('--doc', help='prd.md for fr/nfr, stories.md for us')
    c.add_argument('--key', help='story key when stories.md has no ids yet')
    c.add_argument('--run', help='run slug, for q')

    g = group('clar', 'the clarification log (<runs>/<slug>/clarifications.md)')
    c = cmd(g, 'add', cmd_clar_add, 'append a numbered, dated entry')
    c.add_argument('slug')
    c.add_argument('--asked-by', required=True)
    c.add_argument('--wp', required=True, help='work package or task id, e.g. P2')
    c.add_argument('--owner', required=True, choices=['swf-po', 'swf-architect'])
    c.add_argument('--q', required=True)
    c.add_argument('--a', required=True)
    c.add_argument('--recorded-in', required=True, help='path#section (vX.Y.Z) | not recorded: <why> | needs-human')
    c = cmd(g, 'count', cmd_clar_count, 'questions asked for a work package against the budget of %d' % CLAR_BUDGET)
    c.add_argument('slug')
    c.add_argument('--wp', required=True)
    c.add_argument('--asked-by')
    c.add_argument('--adding', type=int, default=0, help='questions you are about to ask')

    g = group('trace', 'traceability checks')
    c = cmd(g, 'prd', cmd_trace_prd, 'PRD and stories: unique ids, ACs, valid FR/NFR links, no renumbering')
    c.add_argument('prd_dir')
    c.add_argument('--base', help='also check that no id vanished since this ref')
    c = cmd(g, 'hld', cmd_trace_hld, 'every live FR/NFR appears in the HLD Traceability table')
    c.add_argument('hld')
    c.add_argument('--prd', required=True)
    c = cmd(g, 'plan', cmd_trace_plan, 'every must story in exactly one phase; tasks name files and satisfies')
    c.add_argument('plan')
    c.add_argument('--stories', required=True, nargs='+')

    g = group('qa', 'verification mechanics for swf-qa')
    c = cmd(g, 'changed', cmd_qa_changed, 'files changed since BASE, untracked included')
    c.add_argument('base')
    c.add_argument('--under', nargs='+')
    c.add_argument('--lines', action='store_true')
    c.add_argument('--json', action='store_true')
    c = cmd(g, 'coverage', cmd_qa_coverage, 'coverage gate over changed lines (or overall) from lcov/cobertura/json')
    c.add_argument('--base')
    c.add_argument('--report')
    c.add_argument('--format', choices=['lcov', 'cobertura', 'json'])
    c.add_argument('--scope', choices=['changed', 'overall'])
    c.add_argument('--min', type=float)
    c = cmd(g, 'drift', cmd_qa_drift, 'document changes not accounted for by the ledger or clarification log')
    c.add_argument('slug')
    c.add_argument('--base', required=True)
    c = cmd(g, 'weakening', cmd_qa_weakening, 'added test skips, coverage exclusions and coverage-config edits')
    c.add_argument('--base', required=True)

    c = sub.add_parser('level', help='level and track from triage signals',
                       description='Level (highest floor) and track from R D K S G (C = components, optional).')
    c.set_defaults(fn=cmd_level)
    c.add_argument('signals', nargs='+', metavar='R=… D=… K=… S=… G=… [C=…]')
    c.add_argument('--stories', type=int, help='stories added or changed, for R=extend')
    c.add_argument('--tracks', help='the preflight TRACKS line, to apply fallbacks')
    c.add_argument('--phase', help='prefix the LEDGER line with this phase id')

    g = group('gates', 'run the build/test/coverage/lint commands from the config')
    c = cmd(g, 'run', cmd_gates_run, 'run gates, log output under <runs>/<run>/logs/, print one line per gate')
    c.add_argument('gate', choices=['build', 'test', 'coverage', 'lint', 'all'])
    c.add_argument('--run', required=True)
    c.add_argument('--label', help='log file prefix, e.g. P2-r1')
    c.add_argument('--cmd', help='the command to run when the config leaves it empty')
    c.add_argument('--timeout', type=int)
    c.add_argument('--tail', type=int, default=20, help='log lines shown on failure')
    return p


def main(argv=None):
    a = build_parser().parse_args(argv)
    try:
        return a.fn(a)
    except Fail as e:
        print('swf-cli: %s' % e, file=sys.stderr)
        return e.code


if __name__ == '__main__':
    sys.exit(main())
