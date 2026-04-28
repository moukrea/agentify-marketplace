#!/usr/bin/env bash
# bin/test-de-spec-smoke.sh — End-to-end placeholder-substitution smoke.
#
# Renders the agentify source files into /tmp with a custom config
# (company=Acme, skill_prefix=ac, loop.path_root=.scratch-state),
# then asserts:
#   - AGENTS.md / AGENTIFY.md mention 'Acme' (the configured company).
#   - All slash-command references use the configured prefix /ac-*.
#   - All {__AGT_*__} placeholders are consumed in active content.
#   - loop.path_root substitution propagates: .agents-work/ literals
#     in the source were rewritten to .scratch-state/.
#   - AGENTIFY_VERSION marker is written under the custom path_root.
#   - AGENTIFY.md H1 carries a version tag.
#
# Exit 0 on success; non-zero with diagnostic on any failure.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

OUT="$TMP/acme-harness"

fail=0
pass() { printf '  PASS: %s\n' "$1"; }
ng()   { printf '  FAIL: %s\n' "$1"; fail=$((fail+1)); }

echo "=== de-spec smoke: rendering with company=Acme prefix=ac path_root=.scratch-state ==="
"$REPO_ROOT/plugins/agentify/bin/agentify" \
  --company.name=Acme \
  --skills.prefix=ac \
  --plugin.name=agentify \
  --loop.path_root=.scratch-state \
  --output="$OUT" 2>&1 || { echo "agentify failed"; exit 1; }

echo
echo "=== de-spec smoke: assertion 1 — Acme in rendered AGENTIFY.md ==="
if grep -q 'Acme' "$OUT/AGENTIFY.md"; then
  acme_count=$(grep -c 'Acme' "$OUT/AGENTIFY.md")
  pass "AGENTIFY.md mentions Acme ($acme_count occurrences)"
else
  ng "AGENTIFY.md does not mention Acme"
fi

echo
echo "=== de-spec smoke: assertion 2 — /ac- skill prefix substituted ==="
ac_skill_count=$(grep -c '/ac-\|`ac-' "$OUT/AGENTIFY.md" 2>/dev/null || echo 0)
if [ "$ac_skill_count" -gt 0 ]; then
  pass "AGENTIFY.md uses /ac- or 'ac-' skill prefix ($ac_skill_count occurrences)"
else
  ng "AGENTIFY.md has no /ac- or 'ac-' references after substitution"
fi

echo
echo "=== de-spec smoke: assertion 3 — placeholders fully consumed in active content ==="
# Excludes the schema itself (its description text talks about the
# placeholder convention abstractly, e.g., '{__AGT_FIELD__}') and the
# plugin-default config (also meta-documentation).
{
  set +o pipefail
  remaining=$(grep -roE '\{__AGT_[A-Z_]+__\}' "$OUT" 2>/dev/null \
    | grep -vE 'agentify-config\.schema\.json|agentify\.config\.default\.json' \
    | wc -l)
  set -o pipefail
}
remaining=${remaining:-0}
[ "$remaining" = "0" ] && pass "all {__AGT_*__} placeholders substituted in active content" \
                       || ng "$remaining {__AGT_*__} placeholders remain in active content"

echo
echo "=== de-spec smoke: assertion 4 — loop.path_root rewrite (.scratch-state) in active content ==="
# Excludes schema/plugin-default config (they document .agents-work as
# the default value for loop.path_root, which is correct).
{
  set +o pipefail
  agents_work_count=$(grep -rc '\.agents-work' "$OUT" 2>/dev/null \
    | grep -vE 'agentify-config\.schema\.json|agentify\.config\.default\.json' \
    | awk -F: '{s+=$2} END {print s+0}')
  scratch_count=$(grep -rc '\.scratch-state' "$OUT" 2>/dev/null \
    | awk -F: '{s+=$2} END {print s+0}')
  set -o pipefail
}
agents_work_count=${agents_work_count:-0}
scratch_count=${scratch_count:-0}
[ "$agents_work_count" = "0" ] && pass "no .agents-work literals remain in active content" \
                                || ng "$agents_work_count .agents-work literals still in active content"
[ "$scratch_count" -gt 0 ] && pass ".scratch-state populated ($scratch_count occurrences)" \
                            || ng "no .scratch-state references in output"

echo
echo "=== de-spec smoke: assertion 5 — version marker written ==="
if [ -f "$OUT/.scratch-state/AGENTIFY_VERSION" ]; then
  ver=$(cat "$OUT/.scratch-state/AGENTIFY_VERSION")
  pass "$OUT/.scratch-state/AGENTIFY_VERSION = $ver"
else
  ng "AGENTIFY_VERSION marker missing"
fi

echo
echo "=== de-spec smoke: assertion 6 — H1 title rendered for Acme ==="
head1=$(head -1 "$OUT/AGENTIFY.md")
if echo "$head1" | grep -q '(v[0-9]'; then
  pass "AGENTIFY.md H1 carries version: $head1"
else
  ng "AGENTIFY.md H1 missing version: $head1"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "=== de-spec smoke: HEALTHY (all checks pass) ==="
  exit 0
else
  echo "=== de-spec smoke: $fail check(s) failed ==="
  echo "    Tmp output preserved at: $OUT (trap will clean it on exit)"
  exit 1
fi
