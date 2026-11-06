#!/usr/bin/env bash
# Tests for .claude/sw-factory/usage.py against synthetic Claude Code transcripts.
#   bash tests/usage-test.sh
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
USAGE="$SRC/.claude/sw-factory/usage.py"
BASE="$(mktemp -d)"; trap 'rm -rf "$BASE"' EXIT
PROJ="$BASE/proj"; T="$BASE/transcripts"
mkdir -p "$PROJ/.sw-factory" "$T"
printf 'paths:\n  runs: ".sw-factory/runs/"   # quoted, trailing slash\n' > "$PROJ/.sw-factory/config.yaml"
command -v python3 >/dev/null 2>&1 || { echo 'SKIP  python3 not found'; exit 0; }

# Fixtures. S1: an ended sw-manager session with a builder, a po it consulted, an opsx agent and a
# switch to a second run. S2: an open session that also replays one of S1's messages (a fork).
# S3: an ordinary session. S4: a factory session whose usage cannot be parsed.
python3 -I - "$T" "$PROJ" <<'PY'
import json, os, sys
T, PROJ = sys.argv[1], sys.argv[2]

def usage(i=0, w5=0, w1=0, r=0, o=0):
    return {'input_tokens': i, 'cache_creation_input_tokens': w5 + w1, 'cache_read_input_tokens': r,
            'output_tokens': o, 'cache_creation': {'ephemeral_5m_input_tokens': w5, 'ephemeral_1h_input_tokens': w1}}

def asst(mid, model, u, ts, tools=(), side=False):
    content = [{'type': 'tool_use', 'id': t[0], 'name': t[1], 'input': t[2]} for t in tools] or [{'type': 'text', 'text': 'x'}]
    return {'type': 'assistant', 'timestamp': ts, 'isSidechain': side, 'version': '9.9.9',
            'message': {'id': mid, 'model': model, 'usage': u, 'content': content}}

def user(text):
    return {'type': 'user', 'message': {'role': 'user', 'content': text}}

def write(path, lines):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        for l in lines:
            f.write((l if isinstance(l, str) else json.dumps(l)) + '\n')

def sub(session, aid, agent_type, tool_use_id, prompt, msgs, parent=None, depth=1):
    d = os.path.join(T, session, 'subagents')
    write(os.path.join(d, 'agent-%s.jsonl' % aid), [user(prompt)] + msgs)
    meta = {'agentType': agent_type, 'toolUseId': tool_use_id, 'spawnDepth': depth}
    if parent: meta['parentAgentId'] = parent
    write(os.path.join(d, 'agent-%s.meta.json' % aid), [meta])

OPUS, SONNET = 'claude-opus-9', 'claude-sonnet-9'
ledger = PROJ + '/.sw-factory/runs/portal/ledger.md'
builder_prompt = 'TRACK: subagents\nRUN: portal\nWORK PACKAGE: docs/plans/portal.md#P2\nSTORIES: S1\nBASE: abc'
m2_partial = asst('m2', OPUS, usage(i=1, o=1), '2026-01-01T00:00:02Z', [('t-w', 'Write', {'file_path': ledger})])
m2_final = asst('m2', OPUS, usage(i=1, o=50), '2026-01-01T00:00:02Z')
write(os.path.join(T, 'S1.jsonl'), [
    {'type': 'agent-setting', 'agentSetting': 'sw-manager'},
    user('build the portal'),
    asst('m1', OPUS, usage(i=10, w5=1000, o=100), '2026-01-01T00:00:01Z'),
    m2_partial, m2_final,
    asst('m3', OPUS, usage(i=1, r=1000, o=10), '2026-01-01T00:00:03Z',
         [('t-b', 'Agent', {'subagent_type': 'sw-builder', 'prompt': builder_prompt})]),
    asst('m4', OPUS, usage(i=1, r=1100, o=10), '2026-01-01T00:00:04Z',
         [('t-o', 'Agent', {'subagent_type': 'opsx-implementer', 'prompt': 'Apply the change. Be concise.'})]),
    {'type': 'system', 'subtype': 'compact_boundary'},
    asst('m5', OPUS, usage(i=1, r=1200, o=10), '2026-01-01T00:00:05Z',
         [('t-l', 'Bash', {'command': 'cat .sw-factory/runs/other-run/ledger.md'})]),
    asst('m6', OPUS, usage(i=2, w1=500, o=20), '2026-01-01T00:00:06Z'),
    {'type': 'cost-state', 'totalCostUSD': 1.51, 'modelUsage': {
        OPUS: {'costUSD': 1.0, 'inputTokens': 1000, 'outputTokens': 0, 'cacheReadInputTokens': 0, 'cacheCreationInputTokens': 0},
        SONNET: {'costUSD': 0.5, 'inputTokens': 500, 'outputTokens': 0, 'cacheReadInputTokens': 0, 'cacheCreationInputTokens': 0},
        'claude-haiku-aux': {'costUSD': 0.01, 'inputTokens': 10, 'outputTokens': 1}}},
])
sub('S1', 'b', 'sw-builder', 't-b', builder_prompt, [
    asst('b1', SONNET, usage(i=5, w5=2000, o=200), '2026-01-01T00:00:03.1Z', [('t-p', 'Agent', {'subagent_type': 'po', 'prompt': 'MODE: clarify'})]),
    asst('b2', SONNET, usage(i=5, r=2000, o=300), '2026-01-01T00:00:03.5Z')])
sub('S1', 'p', 'po', 't-p', 'MODE: clarify\nIs the date local or UTC?', [
    asst('p1', OPUS, usage(i=3, w5=900, o=40), '2026-01-01T00:00:03.2Z')], parent='b', depth=2)
sub('S1', 'o', 'opsx-implementer', 't-o', 'Apply the change. Be concise.', [
    asst('o1', SONNET, usage(i=7, w5=700, o=70), '2026-01-01T00:00:04.1Z')])

qa_prompt = 'TRACK: subagents\nRUN: portal\nWORK PACKAGE: docs/plans/portal.md#P2\nROUND: 1\nFINDINGS PATH: .sw-factory/runs/portal/qa-P2-1.md'
write(os.path.join(T, 'S2.jsonl'), [
    {'type': 'agent-setting', 'agentSetting': 'sw-manager'},
    asst('m1', OPUS, usage(i=10, w5=1000, o=100), '2026-01-01T00:00:01Z'),  # replayed from S1
    asst('m7', OPUS, usage(i=4, r=300, o=30), '2026-01-02T00:00:01Z',
         [('t-q', 'Agent', {'subagent_type': 'sw-qa', 'prompt': qa_prompt})]),
])
sub('S2', 'q', 'sw-qa', 't-q', qa_prompt, [asst('q1', OPUS, usage(i=6, w5=600, o=60), '2026-01-02T00:00:02Z')])

write(os.path.join(T, 'S3.jsonl'), [user('hello'), asst('n1', OPUS, usage(i=99, o=99), '2026-01-03T00:00:00Z')])
write(os.path.join(T, 'S4.jsonl'), [{'type': 'agent-setting', 'agentSetting': 'sw-manager'},
                                    {'type': 'assistant', 'message': {'id': 'z', 'content': []}}])
PY

pass=0 fail=0
check() { # check <description> <python expression over `rows`, `total`, `err`>
  if python3 -I -c "import json, sys
d = json.load(open(sys.argv[1])); rows, total = d['rows'], d['total']; err = open(sys.argv[2]).read()
row = lambda **k: [r for r in rows if all(r.get(a) == b for a, b in k.items())]
sys.exit(0 if ($2) else 1)" "$OUT" "$ERR" 2>/dev/null; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FAIL  %s\n' "$1"; fi
}
report() { OUT="$BASE/out.json" ERR="$BASE/err.txt"; python3 -I "$USAGE" report --project "$PROJ" --transcripts "$T" --format json "$@" > "$OUT" 2> "$ERR"; }

report --by session
check 'ordinary session S3 is ignored'            "{r['session'] for r in rows} == {'S1', 'S2'}"
check 'unparseable factory session S4 is reported' "'S4' in err and 'not recognised' in err"
check 'S1 total equals Claude Code cost-state'     "abs(sum(r['cost_usd'] for r in row(session='S1')) - 1.51) < 1e-9 and not any(r['estimated'] for r in row(session='S1'))"
check 'open session S2 is priced from S1 rates'    "row(session='S2')[0]['estimated'] and row(session='S2')[0]['cost_usd'] > 0"

report --by model
# opus: m1 + m2(final) + m3..m6 + p1 + m7 + q1; m1 once although S2 replays it, m2 output 50 not 1.
check 'dedup: last copy wins, replayed id once'   "row(model='claude-opus-9', run='portal')[0]['output'] + row(model='claude-opus-9', run='other-run')[0]['output'] == 100+50+10+10+10+20+40+30+60"
check 'auxiliary model cost kept as overhead'     "abs(sum(r['cost_usd'] for r in row(model='claude-haiku-aux')) - 0.01) < 1e-9"

report --by agent
check 'builder: run, phase, track from its prompt' "row(agent='sw-builder', run='portal', phase='P2', track='subagents')"
check 'nested po inherits run+phase from builder'  "row(agent='po', run='portal', phase='P2')"
check 'opsx agent inherits the main session state' "row(agent='opsx-implementer', run='portal', phase='P2')"
check 'sw-qa phase from FINDINGS PATH'             "row(agent='sw-qa', run='portal', phase='P2')"
check 'main switches run at the run-state path'    "row(agent='sw-manager', run='other-run')[0]['output'] == 20 and row(agent='sw-manager', run='portal', phase=None)"
check 'peak context of the builder'                "row(agent='sw-builder')[0]['peak_context'] == 2005"
check 'spawn counts exclude the main session'      "row(agent='sw-builder')[0]['spawns'] == 1 and row(agent='sw-manager', run='portal')[0]['spawns'] == 0"

report portal --by run
check 'run filter'                                 "[r['run'] for r in rows] == ['portal']"

# Snapshots outlive transcripts.
[ -f "$PROJ/.sw-factory/runs/.usage/S1.json" ] && pass=$((pass + 1)) || { fail=$((fail + 1)); echo 'FAIL  snapshot written under the configured runs path'; }
rm -rf "$T/S1.jsonl" "$T/S1"
report --by session
check 'deleted transcript still reported'          "abs(sum(r['cost_usd'] for r in row(session='S1')) - 1.51) < 1e-9"

# The SessionEnd hook is silent, always exits 0, and returns at once.
for input in 'not json' '' '[1]' '{"transcript_path":"/nope.jsonl","cwd":"/nonexistent"}'; do
  out="$(printf '%s' "$input" | python3 -I "$USAGE" snapshot --hook 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$out" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FAIL  hook on %q: rc=%s out=%s\n' "$input" "$rc" "$out"; fi
done
rm -f "$PROJ/.sw-factory/runs/.usage/S2.json"
out="$(printf '{"transcript_path":"%s","cwd":"%s"}' "$T/S2.jsonl" "$PROJ" | env -u CLAUDE_PROJECT_DIR python3 -I "$USAGE" snapshot --hook 2>&1)"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28; do  # child waits ≤5 s for cost-state
  [ -f "$PROJ/.sw-factory/runs/.usage/S2.json" ] && break; sleep 0.25
done
if [ -z "$out" ] && [ -f "$PROJ/.sw-factory/runs/.usage/S2.json" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo 'FAIL  hook snapshots its session'; fi

echo "usage.py: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
