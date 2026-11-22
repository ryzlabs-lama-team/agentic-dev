#!/usr/bin/env bash
# Tests for the OpenCode distribution: install.sh --target, the .opencode/ tree's invariants, and
# the swf-guard plugin (its hooks driven directly; needs node ≥ 22.18 for TypeScript type-stripping).
#   bash tests/opencode-test.sh
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="$(mktemp -d)"; trap 'rm -rf "$BASE"' EXIT
pass=0 fail=0
check() { # check <description> <command…>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FAIL  %s\n' "$desc"; fi
}
newrepo() { local d="$BASE/$1"; mkdir -p "$d" && git -C "$d" init -q && printf '%s' "$d"; }
AGENTS="swf-manager swf-po swf-architect swf-planner swf-builder swf-builder-hard swf-qa"

# --- source tree invariants ---------------------------------------------------------------
check "no .claude/ path in OpenCode agents or overlays" \
  bash -c "! grep -rn '\.claude/' '$SRC/.opencode' | grep -v '\.claude/\*\*\|\.claude/ \.opencode/\|\.claude/swf-tools/ or'"
check "no Claude-only tool names in the OpenCode tree" \
  bash -c "! grep -rnE 'AskUserQuestion|SendMessage|NotebookEdit|model: \"opus\"|claude --agent' '$SRC/.opencode'"
for a in $AGENTS; do
  f="$SRC/.opencode/agents/$a.md"
  check "$a: description, mode and model in frontmatter" \
    bash -c "awk 'NR==1&&!/^---\$/{exit 1} NR>1&&/^---\$/{exit} 1' '$f' | grep -q '^description: ' && grep -q '^mode: ' '$f' && grep -q '^model: github-copilot/' '$f'"
  check "$a: subagent spawning stated explicitly" grep -q '^  task:' "$f"
done
check "swf-manager is the only primary agent" \
  bash -c "[ \"\$(grep -l '^mode: primary' '$SRC'/.opencode/agents/*.md)\" = '$SRC/.opencode/agents/swf-manager.md' ]"
check "swf-manager holds the question tool"           grep -q '^  question: allow' "$SRC/.opencode/agents/swf-manager.md"
check "swf-manager has no read/edit/bash deny"        bash -c "! grep -qE '^  (read|edit|bash):' '$SRC/.opencode/agents/swf-manager.md'"
check "swf-builder-hard is hidden"                    grep -q '^hidden: true' "$SRC/.opencode/agents/swf-builder-hard.md"
check "swf-builder-hard delegates to swf-builder.md"  grep -q '\.opencode/agents/swf-builder\.md' "$SRC/.opencode/agents/swf-builder-hard.md"
check "swf-builder-hard does not restate the payload" bash -c "! grep -q 'Return payload' '$SRC/.opencode/agents/swf-builder-hard.md'"
check "tiers match the Claude tree (builder sonnet)"  grep -q '^model: github-copilot/claude-sonnet' "$SRC/.opencode/agents/swf-builder.md"
check "plugin file exports only the plugin" \
  bash -c "[ \"\$(grep -c '^export ' '$SRC/.opencode/plugins/swf-guard.ts')\" = 1 ]"

# --- installer ----------------------------------------------------------------------------
R="$(newrepo default)"
"$SRC/install.sh" "$R" >/dev/null 2>&1
check "default target is claude"                     test -f "$R/.claude/agents/swf/swf-manager.md"
check "default target installs no OpenCode tree"     test ! -e "$R/.opencode"

SHARED="swf-cli.py usage.py hooks/guard.sh references/track-selection.md templates/prd.md templates/config.yaml"
R="$(newrepo oc)"
out="$("$SRC/install.sh" --target opencode "$R" 2>&1)"
check "opencode: install succeeds"                   test -f "$R/.opencode/.sw-factory-install-manifest"
for a in $AGENTS; do check "opencode: agent $a" test -f "$R/.opencode/agents/$a.md"; done
check "opencode: plugin installed"                   test -f "$R/.opencode/plugins/swf-guard.ts"
for f in $SHARED; do
  check "opencode: shared $f installed once, in .sw-factory/tools" cmp -s "$SRC/.sw-factory/tools/$f" "$R/.sw-factory/tools/$f"
  check "opencode: shared $f not copied into .opencode"          test ! -e "$R/.opencode/swf-tools/$f"
done
check "opencode: protocol is the OpenCode one"       cmp -s "$SRC/.opencode/swf-tools/protocols/clarification.md" "$R/.opencode/swf-tools/protocols/clarification.md"
check "opencode: preflight is the OpenCode one"      cmp -s "$SRC/.opencode/swf-tools/preflight.sh" "$R/.opencode/swf-tools/preflight.sh"
check "opencode: playbooks are the OpenCode ones"    cmp -s "$SRC/.opencode/swf-tools/references/tracks/opsx-loop.md" "$R/.opencode/swf-tools/references/tracks/opsx-loop.md"
check "opencode: no .claude tree"                    test ! -e "$R/.claude"
check "opencode: no opencode.json written"           bash -c "! ls '$R'/opencode.json* 2>/dev/null"
check "opencode: config created"                     test -f "$R/.sw-factory/config.yaml"
check "opencode: run state gitignored"               grep -q '^\.sw-factory/runs/' "$R/.gitignore"
check "opencode: scripts executable"                 test -x "$R/.opencode/swf-tools/preflight.sh" -a -x "$R/.sw-factory/tools/swf-cli.py" -a -x "$R/.sw-factory/tools/hooks/guard.sh"
check "opencode: manifest lists only .opencode/"     bash -c "! grep -v '  \.opencode/' '$R/.opencode/.sw-factory-install-manifest'"
check "opencode: shared manifest lists only tools"   bash -c "! grep -v '  \.sw-factory/tools/' '$R/.sw-factory/.install-manifest'"
check "opencode: next step names opencode"           grep -q 'opencode --agent swf-manager' <<<"$out"
check "opencode: swf-cli runs from the shared tools" bash -c "cd '$R' && python3 .sw-factory/tools/swf-cli.py --version"
check "opencode: reinstall is all identical" \
  bash -c "! '$SRC/install.sh' --target opencode '$R' 2>&1 | grep -E '^  (new|stale|customized|removed) '"
echo '# mine' >> "$R/.opencode/agents/swf-qa.md"
check "opencode: refuses to clobber a customized agent" bash -c "! '$SRC/install.sh' --target opencode '$R'"
check "opencode: --force overwrites it" \
  bash -c "'$SRC/install.sh' --force --target opencode '$R' && cmp -s '$SRC/.opencode/agents/swf-qa.md' '$R/.opencode/agents/swf-qa.md'"
cp "$SRC/.sw-factory/tools/templates/lld.md" "$BASE/old-lld" && echo stale >> "$BASE/old-lld"
cp "$BASE/old-lld" "$R/.sw-factory/tools/templates/lld.md"
sed -i.bak "s#^[0-9a-f]*  \.sw-factory/tools/templates/lld\.md#$(shasum -a 256 "$BASE/old-lld" | awk '{print $1}')  .sw-factory/tools/templates/lld.md#" "$R/.sw-factory/.install-manifest"
check "shared: a stale (unmodified older) tool is updated" \
  bash -c "'$SRC/install.sh' --target opencode '$R' | grep -q '^  stale  \.sw-factory/tools/templates/lld\.md'"

R="$(newrepo all)"
"$SRC/install.sh" --target all "$R" >/dev/null 2>&1
check "all: Claude agents"                           test -f "$R/.claude/agents/swf/swf-qa.md"
check "all: OpenCode agents"                         test -f "$R/.opencode/agents/swf-builder-hard.md"
check "all: one copy of the shared tools"            bash -c "[ ! -e '$R/.claude/swf-tools/swf-cli.py' ] && [ ! -e '$R/.opencode/swf-tools/swf-cli.py' ] && [ -f '$R/.sw-factory/tools/swf-cli.py' ]"
check "all: Claude hook runs the shared guard"       grep -q '/.sw-factory/tools/hooks/guard.sh' "$R/.claude/settings.json"
check "all: Claude usage hook runs the shared usage.py" grep -q '/.sw-factory/tools/usage.py' "$R/.claude/settings.json"
check "all: swf-cli allowed at its shared path"      grep -qF 'Bash(python3 .sw-factory/tools/swf-cli.py:*)' "$R/.claude/settings.json"
check "all: three manifests" \
  test -f "$R/.claude/.sw-factory-install-manifest" -a -f "$R/.opencode/.sw-factory-install-manifest" -a -f "$R/.sw-factory/.install-manifest"
check "all: Claude manifest lists only Claude files" bash -c "! grep -qv '  \.claude/' '$R/.claude/.sw-factory-install-manifest'"
check "all: Claude preflight passes"                 bash -c "cd '$R' && bash .claude/swf-tools/preflight.sh"

# Upgrade from the layout that copied the shared tools into each runtime's swf-tools/.
R="$(newrepo upgrade)"
"$SRC/install.sh" --target all "$R" >/dev/null 2>&1
for rt in claude opencode; do
  for f in swf-cli.py usage.py hooks/guard.sh templates/plan.md; do
    mkdir -p "$(dirname "$R/.$rt/swf-tools/$f")"; cp "$SRC/.sw-factory/tools/$f" "$R/.$rt/swf-tools/$f"
  done
done
cp "$SRC/.sw-factory/tools/templates/prd.md" "$R/.opencode/swf-tools/templates/prd.md"; echo '# mine' >> "$R/.opencode/swf-tools/templates/prd.md"
cat > "$R/.claude/settings.json" <<'JSON'
{"permissions": {"allow": ["Bash(python3 .claude/swf-tools/swf-cli.py:*)"]},
 "hooks": {"PreToolUse": [{"matcher": "Write|Edit|NotebookEdit|Agent|Task", "hooks": [{"type": "command", "command": "bash \"${CLAUDE_PROJECT_DIR}/.claude/swf-tools/hooks/guard.sh\""}]}],
           "SessionEnd": [{"hooks": [{"type": "command", "command": "python3 \"${CLAUDE_PROJECT_DIR}/.claude/swf-tools/usage.py\" snapshot --hook"}]}]}}
JSON
"$SRC/install.sh" --target opencode "$R" > "$BASE/up1.out" 2>&1
check "upgrade: opencode-only leaves Claude's old copies"  test -f "$R/.claude/swf-tools/hooks/guard.sh"
check "upgrade: opencode's unmodified old copies removed"  bash -c "[ ! -e '$R/.opencode/swf-tools/swf-cli.py' ] && [ ! -e '$R/.opencode/swf-tools/hooks' ]"
check "upgrade: a customized old copy is kept"             test -f "$R/.opencode/swf-tools/templates/prd.md"
check "upgrade: and reported"                              grep -q 'templates/prd.md is customized and was left in place' "$BASE/up1.out"
"$SRC/install.sh" --target all "$R" > "$BASE/up2.out" 2>&1
check "upgrade: Claude's old copies removed"               bash -c "[ ! -e '$R/.claude/swf-tools/swf-cli.py' ] && [ ! -e '$R/.claude/swf-tools/hooks' ] && [ ! -e '$R/.claude/swf-tools/templates' ]"
check "upgrade: settings repointed at the shared tools"    bash -c "! grep -q '\.claude/swf-tools/\(hooks\|usage\|swf-cli\)' '$R/.claude/settings.json' && grep -q '\.sw-factory/tools/hooks/guard\.sh' '$R/.claude/settings.json'"
check "upgrade: hooks not wired twice"                     bash -c "[ \"\$(grep -o 'tools/hooks/guard.sh' '$R/.claude/settings.json' | wc -l | tr -d ' ')\" = 1 ]"
check "upgrade: permission not added twice"                bash -c "[ \"\$(grep -o 'swf-cli.py:\*' '$R/.claude/settings.json' | wc -l | tr -d ' ')\" = 1 ]"
check "upgrade: runtime-specific files stay"               test -f "$R/.claude/swf-tools/preflight.sh" -a -f "$R/.claude/swf-tools/protocols/clarification.md"
check "bad --target is a usage error"                bash -c "! '$SRC/install.sh' --target vscode '$R'"

# --- plugin -------------------------------------------------------------------------------
R="$BASE/oc"   # installed above with --target opencode
mkdir -p "$R/docs/prds"
if node -e 'process.exit(+process.versions.node.split(".")[0] >= 23 ? 0 : 1)' 2>/dev/null; then
  plugin_out="$(cd "$R" && node --no-warnings - "$R" <<'JS' 2>&1
const root = process.argv[2]
const { SwfGuard } = await import(root + '/.opencode/plugins/swf-guard.ts')
const sessions = { 'ses-qa': 'swf-qa' }
const client = { session: { get: async ({ path }) => {
  if (path.id === 'ses-broken') throw new Error('no such session')
  return { data: { agent: sessions[path.id] } }
} } }
const h = await SwfGuard({ client, directory: root })
const results = []
const t = async (name, want, fn) => {
  let got = 'allow'
  try { await fn() } catch (e) { got = /sw-factory guard/.test(e.message) ? 'block' : 'error: ' + e.message }
  results.push((got === want ? 'PASS ' : 'FAIL ') + name + (got === want ? '' : ` (want ${want}, got ${got})`))
}
const call = (sessionID, tool, args) => h['tool.execute.before']({ tool, sessionID, callID: 'c' }, { args })
const cfg1 = {}; await h.config(cfg1)
results.push((cfg1.subagent_depth === 3 ? 'PASS ' : 'FAIL ') + 'config: raises subagent_depth to 3')
const cfg2 = { subagent_depth: 5 }; await h.config(cfg2)
results.push((cfg2.subagent_depth === 5 ? 'PASS ' : 'FAIL ') + 'config: keeps a higher subagent_depth')
await h['chat.message']({ sessionID: 'ses-b', agent: 'swf-builder' }, {})
await h['chat.message']({ sessionID: 'ses-m', agent: 'swf-manager' }, {})
await h['chat.message']({ sessionID: 'ses-build', agent: 'build' }, {})
await t('builder write code', 'allow', () => call('ses-b', 'write', { filePath: root + '/src/a.ts' }))
await t('builder write PRD', 'block', () => call('ses-b', 'write', { filePath: root + '/docs/prds/x/prd.md' }))
await t('builder edit relative PRD path', 'block', () => call('ses-b', 'edit', { filePath: 'docs/prds/x/prd.md' }))
await t('builder edit the plugin', 'block', () => call('ses-b', 'edit', { filePath: root + '/.opencode/plugins/swf-guard.ts' }))
await t('builder patch code only', 'allow', () => call('ses-b', 'apply_patch', { patchText: '*** Begin Patch\n*** Add File: src/b.ts\n+x\n*** End Patch' }))
await t('builder patch hides a PRD among code', 'block', () => call('ses-b', 'apply_patch', { patchText: '*** Begin Patch\n*** Add File: src/b.ts\n+x\n*** Update File: docs/prds/x/prd.md\n@@\n-a\n+b\n*** End Patch' }))
await t('builder patch moves code into ADRs', 'block', () => call('ses-b', 'apply_patch', { patchText: '*** Begin Patch\n*** Update File: src/b.ts\n*** Move to: docs/adrs/0001-x.md\n@@\n-a\n+b\n*** End Patch' }))
await t('builder patch deletes the config', 'block', () => call('ses-b', 'apply_patch', { patchText: '*** Begin Patch\n*** Delete File: .sw-factory/config.yaml\n*** End Patch' }))
await t('builder consults swf-po', 'allow', () => call('ses-b', 'task', { subagent_type: 'swf-po', prompt: 'p', description: 'd' }))
await t('builder spawns swf-qa', 'block', () => call('ses-b', 'task', { subagent_type: 'swf-qa', prompt: 'p', description: 'd' }))
await t('manager writes run state', 'allow', () => call('ses-m', 'write', { filePath: root + '/.sw-factory/runs/x/ledger.md' }))
await t('manager writes code', 'block', () => call('ses-m', 'write', { filePath: root + '/src/a.ts' }))
await t('manager bash is not governed', 'allow', () => call('ses-m', 'bash', { command: 'echo > src/a.ts' }))
await t('agent from session lookup (swf-qa writes code)', 'block', () => call('ses-qa', 'write', { filePath: root + '/src/a.ts' }))
await t('unknown session is not governed', 'allow', () => call('ses-broken', 'write', { filePath: root + '/docs/prds/x/prd.md' }))
await t('non-factory agent is not governed', 'allow', () => call('ses-build', 'write', { filePath: root + '/docs/prds/x/prd.md' }))
await h['chat.message']({ sessionID: 'ses-b', agent: 'build' }, {})
await t('agent switch in a session is followed', 'allow', () => call('ses-b', 'write', { filePath: root + '/docs/prds/x/prd.md' }))
const env = { env: {} }; await h['shell.env']({ cwd: root }, env)
results.push((env.env.SWF_RUNTIME === 'opencode' ? 'PASS ' : 'FAIL ') + 'shell.env: tells the shared tools the runtime')
try { await call('ses-m', 'write', { filePath: root + '/src/a.ts' }) } catch (e) {
  results.push((/\.opencode\/swf-tools\/protocols\/clarification\.md/.test(e.message) ? 'PASS ' : 'FAIL ') + 'block message names the OpenCode protocol')
}
console.log(results.join('\n'))
JS
)"
  while IFS= read -r line; do
    case "$line" in
      PASS*) pass=$((pass + 1)) ;;
      FAIL*) fail=$((fail + 1)); printf 'FAIL  plugin: %s\n' "${line#FAIL }" ;;
      *) fail=$((fail + 1)); printf 'FAIL  plugin: %s\n' "$line" ;;
    esac
  done <<<"$plugin_out"
else
  echo "skip  plugin tests (node ≥ 23 not found)"
fi

echo "opencode: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
