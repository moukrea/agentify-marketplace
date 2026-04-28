#!/usr/bin/env bash
# bin/test-plugin-install-smoke.sh — End-to-end install-readiness smoke
# for WS-C-009. Validates that the marketplace + plugin layout is
# structurally complete enough that `claude /plugin marketplace add
# file://<repo>` and `claude /plugin install agentify@agentify-marketplace`
# would succeed.
#
# We don't run the actual `claude` install non-interactively because
# that requires an interactive Claude Code session. Instead we exercise
# (a) JSON schema validity for every required manifest, (b) presence and
# correctness of every declared skill / hook / template asset, and (c)
# the rendering pipeline (bin/agentify into a tmp dir mirrors what an
# in-target install + agentification would produce).
#
# Optional: if the `claude` CLI is present and supports a non-interactive
# probe, run a live `--dry-run` install via onboard.sh. Skipped otherwise.
#
# Exit 0 on success; non-zero with diagnostic on any failure.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
pass() { printf '  PASS: %s\n' "$1"; }
ng()   { printf '  FAIL: %s\n' "$1"; fail=$((fail+1)); }
skip() { printf '  SKIP: %s\n' "$1"; }

echo "=== plugin-install smoke: manifest validity ==="
jq empty .claude-plugin/marketplace.json && pass ".claude-plugin/marketplace.json valid JSON" \
  || ng ".claude-plugin/marketplace.json invalid"
jq -e '.name and .plugins and (.plugins | length > 0)' .claude-plugin/marketplace.json >/dev/null \
  && pass ".claude-plugin/marketplace.json has name + plugins[]" \
  || ng ".claude-plugin/marketplace.json missing required keys"

jq empty plugins/agentify/.claude-plugin/plugin.json && pass "plugin.json valid JSON" \
  || ng "plugin.json invalid"
jq -e '.name and .version' plugins/agentify/.claude-plugin/plugin.json >/dev/null \
  && pass "plugin.json has name + version" \
  || ng "plugin.json missing required keys"

jq empty plugins/agentify/.claude-plugin/managed-settings.template.json \
  && pass "managed-settings.template.json valid JSON" \
  || ng "managed-settings.template.json invalid"

jq empty plugins/agentify/hooks/hooks.json && pass "hooks.json valid JSON" \
  || ng "hooks.json invalid"

jq empty plugins/agentify/agentify-config.schema.json && pass "agentify-config.schema.json valid JSON" \
  || ng "agentify-config.schema.json invalid"

jq empty plugins/agentify/agentify.config.default.json && pass "agentify.config.default.json valid JSON" \
  || ng "agentify.config.default.json invalid"

echo
echo "=== plugin-install smoke: declared skills present ==="
# Expected skills bundled with the agentify plugin. /agt-loop is sourced
# from .claude/skills/agt-loop/ at the marketplace root (it's the
# self-loop driver and not packaged inside plugins/agentify/). The
# remaining five (including the v4.3 /agentify entry skill from T03)
# live under plugins/agentify/skills/.
declared="agentify agt-config agt-upgrade agt-self-improve agt-feedback"
declared_count=0
for skill in $declared; do
  declared_count=$((declared_count+1))
  if [ -f "plugins/agentify/skills/$skill/SKILL.md" ]; then
    pass "skill present: $skill"
  else
    ng "expected skill missing: plugins/agentify/skills/$skill/SKILL.md"
  fi
done
[ "$declared_count" -ge 5 ] && pass "declared-skill list has $declared_count entries (>=5 expected)" \
                            || ng "declared-skill list shrank to $declared_count (expected >=5)"
# /agt-loop ships at .claude/skills/ for self-driving the marketplace repo.
test -f .claude/skills/agt-loop/SKILL.md && pass "self-loop skill present (.claude/skills/agt-loop/)" \
                                         || ng "self-loop SKILL.md missing"

echo
echo "=== plugin-install smoke: declared hooks present + executable ==="
hook_paths=$(jq -r '.. | objects | select(has("command")) | .command' plugins/agentify/hooks/hooks.json \
  | grep -oE '\${CLAUDE_PLUGIN_ROOT}/hooks/[^ ]+\.sh' | sed 's|\${CLAUDE_PLUGIN_ROOT}/|plugins/agentify/|' | sort -u)
hook_count=0
for h in $hook_paths; do
  hook_count=$((hook_count+1))
  if [ -f "$h" ] && [ -x "$h" ]; then
    pass "hook executable: $(basename "$h")"
  elif [ -f "$h" ]; then
    ng "hook present but not executable: $h"
  else
    ng "hook missing: $h"
  fi
done
[ "$hook_count" -gt 0 ] && pass "found $hook_count declared hooks" \
                        || ng "no hooks declared in hooks.json (expected at least 4)"

echo
echo "=== plugin-install smoke: rendering pipeline (plugins/agentify/bin/agentify into tmp) ==="
TARGET="$TMP/install-target"
"$REPO_ROOT/plugins/agentify/bin/agentify" \
  --company.name='ProbeCo' \
  --skills.prefix=pr \
  --output="$TARGET" >"$TMP/agentify.log" 2>&1
if [ $? -eq 0 ] && [ -f "$TARGET/AGENTIFY.md" ]; then
  pass "plugins/agentify/bin/agentify rendered cleanly into $TARGET"
else
  ng "plugins/agentify/bin/agentify failed:"
  sed 's/^/    /' "$TMP/agentify.log" | head -10
fi

# The rendered target should look like an installable agentify harness.
test -f "$TARGET/AGENTIFY.md"               && pass "rendered AGENTIFY.md present"               || ng "missing rendered AGENTIFY.md"
test -f "$TARGET/lib/resolve_config.sh"     && pass "rendered lib/resolve_config.sh present"     || ng "missing rendered lib/resolve_config.sh"
test -f "$TARGET/.agents-work/AGENTIFY_VERSION" 2>/dev/null \
  || test -f "$TARGET/.scratch-state/AGENTIFY_VERSION" 2>/dev/null \
  && pass "version marker written by render" \
  || ng "version marker missing (expected at <loop.path_root>/AGENTIFY_VERSION)"

# Pull the version that was written.
version=""
[ -f "$TARGET/.agents-work/AGENTIFY_VERSION" ] && version=$(cat "$TARGET/.agents-work/AGENTIFY_VERSION")
echo "    rendered version: ${version:-(unknown)}"

echo
echo "=== plugin-install smoke: onboard.sh dry-run ==="
DRY_OUT=$(MARKETPLACE_URL=https://github.com/moukrea/agentify-marketplace \
          MARKETPLACE_NAME=agentify-marketplace \
          PLUGIN_NAME=agentify \
          bash plugins/agentify/bin/onboard.sh --dry-run 2>&1)
echo "$DRY_OUT" | grep -q 'plugin marketplace add' && pass "dry-run prints 'plugin marketplace add'" \
                                                   || ng "dry-run missing 'plugin marketplace add'"
echo "$DRY_OUT" | grep -q 'plugin install agentify' && pass "dry-run prints 'plugin install agentify'" \
                                                    || ng "dry-run missing 'plugin install agentify'"

echo
echo "=== plugin-install smoke: optional live install probe ==="
if command -v claude >/dev/null 2>&1; then
  # The actual install requires an interactive Claude Code session. We
  # check only the most basic CLI presence here. A real install probe
  # would need 'claude --print "/plugin marketplace list"' to be safely
  # invokable, which depends on CLI version and authenticated context.
  skip "claude CLI present, but live install requires interactive session — covered by manual onboarding runbook"
else
  skip "claude CLI not on PATH; structural validation only"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "=== plugin-install smoke: HEALTHY (all structural checks pass) ==="
  echo "agentify plugin v${version:-?} active in $TARGET"
  exit 0
else
  echo "=== plugin-install smoke: $fail check(s) failed ==="
  exit 1
fi
