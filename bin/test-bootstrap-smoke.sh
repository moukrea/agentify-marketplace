#!/usr/bin/env bash
# bin/test-bootstrap-smoke.sh — End-to-end /agentify bootstrap-flow smoke.
#
# Validates the v4.3 plugin-distribution patch: the /agentify slash
# command (plugins/agentify/skills/agentify/SKILL.md) and the renderer
# at plugins/agentify/bin/agentify must work both at dev time (running
# from the marketplace repo) and in install-cache simulation (with
# ${CLAUDE_PLUGIN_ROOT} pointed at a copy of plugins/agentify/).
#
# Sections:
#   1. SKILL.md sanity (frontmatter, allowed-tools format, references
#      to ${CLAUDE_PLUGIN_ROOT} + AGENTIFY.md + bin/agentify).
#   2. Direct invocation of plugins/agentify/bin/agentify and
#      assertions on the rendered target (placeholder substitution,
#      version marker, four-file context bundle, custom path_root).
#   3. Plugin-install simulation via copying plugins/agentify/ to a
#      tmp dir and invoking bin/agentify with CLAUDE_PLUGIN_ROOT=<tmp>.
#   4. SKILL.md vs install-smoke parity (the agentify skill is in the
#      declared skill list of test-plugin-install-smoke.sh).
#
# Exit 0 on success; non-zero with diagnostics on any failure.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
pass() { printf '  PASS: %s\n' "$1"; }
ng()   { printf '  FAIL: %s\n' "$1"; fail=$((fail+1)); }

SKILL="$REPO_ROOT/plugins/agentify/skills/agentify/SKILL.md"

echo "=== bootstrap smoke: section 1 — /agentify SKILL.md sanity ==="
if [ -f "$SKILL" ]; then pass "SKILL.md exists at $SKILL"; else ng "SKILL.md missing at $SKILL"; fi
if head -1 "$SKILL" | grep -q '^---$'; then pass "frontmatter open fence"; else ng "frontmatter open fence missing on line 1"; fi
if grep -q '^description:' "$SKILL"; then pass "description field present"; else ng "description field missing"; fi
if grep -q '^allowed-tools:' "$SKILL"; then pass "allowed-tools field present"; else ng "allowed-tools field missing"; fi
# allowed-tools must be space-separated, not comma-separated.
if grep -E '^allowed-tools:.*,' "$SKILL" >/dev/null; then
  ng "allowed-tools is comma-separated (must be space-separated per canonical schema)"
else
  pass "allowed-tools is space-separated"
fi
if grep -q 'CLAUDE_PLUGIN_ROOT' "$SKILL"; then pass "CLAUDE_PLUGIN_ROOT referenced"; else ng "CLAUDE_PLUGIN_ROOT not referenced — env-var path resolution undocumented"; fi
if grep -q 'AGENTIFY.md' "$SKILL"; then pass "AGENTIFY.md referenced"; else ng "AGENTIFY.md not referenced — bootstrap target unclear"; fi
if grep -q 'bin/agentify' "$SKILL"; then pass "bin/agentify referenced"; else ng "bin/agentify not referenced — renderer invocation missing"; fi

echo
echo "=== bootstrap smoke: section 2 — direct invocation + rendered output ==="
OUT="$TMP/target"
"$REPO_ROOT/plugins/agentify/bin/agentify" \
  --company.name=BootProbe \
  --skills.prefix=bp \
  --loop.path_root=.work \
  --output="$OUT" >"$TMP/render.log" 2>&1 \
  || { ng "renderer exited non-zero (see $TMP/render.log)"; cat "$TMP/render.log"; }

if [ -f "$OUT/AGENTIFY.md" ]; then pass "AGENTIFY.md rendered"; else ng "AGENTIFY.md missing in rendered target"; fi
if [ -f "$OUT/AGENTIFY.md" ] && grep -q 'BootProbe' "$OUT/AGENTIFY.md"; then
  pass "company.name substituted (BootProbe)"
else
  ng "company.name not substituted — AGENTIFY.md missing 'BootProbe'"
fi
if [ -f "$OUT/AGENTIFY.md" ] && grep -q '/bp-' "$OUT/AGENTIFY.md"; then
  pass "skill prefix substituted (/bp-)"
else
  ng "skill prefix not substituted — AGENTIFY.md missing '/bp-'"
fi
if [ -f "$OUT/LOOP_PROMPT.md" ]; then pass "LOOP_PROMPT.md rendered"; else ng "LOOP_PROMPT.md missing"; fi
if [ -f "$OUT/lib/resolve_config.sh" ]; then
  if [ -x "$OUT/lib/resolve_config.sh" ]; then pass "lib/resolve_config.sh present + executable"; else ng "lib/resolve_config.sh present but NOT executable"; fi
else
  ng "lib/resolve_config.sh missing in rendered target"
fi
for ctx in claude-code-mechanics external-research known-bugs verification-cookbook; do
  if [ -f "$OUT/context/$ctx.md" ]; then pass "context/$ctx.md rendered"; else ng "context/$ctx.md missing"; fi
done
if [ -f "$OUT/agentify-config.schema.json" ]; then pass "agentify-config.schema.json carried over"; else ng "agentify-config.schema.json missing"; fi
if [ -f "$OUT/agentify.config.default.json" ]; then pass "agentify.config.default.json carried over"; else ng "agentify.config.default.json missing"; fi

# Custom loop.path_root: marker should land at .work/, not .agents-work/.
if [ -f "$OUT/.work/AGENTIFY_VERSION" ]; then
  pass "AGENTIFY_VERSION written under custom path_root (.work/)"
  ver="$(cat "$OUT/.work/AGENTIFY_VERSION")"
  if echo "$ver" | grep -qE '^v4\.[0-9]+$'; then
    pass "AGENTIFY_VERSION matches /v4\\.[0-9]+/ ($ver)"
  else
    ng "AGENTIFY_VERSION malformed: '$ver'"
  fi
else
  ng "AGENTIFY_VERSION missing under .work/ — custom path_root substitution failed"
fi
# .agents-work should NOT exist (path_root override should have rewritten it).
if [ -d "$OUT/.agents-work" ]; then
  ng ".agents-work/ leaked into rendered target despite --loop.path_root=.work"
else
  pass ".agents-work/ correctly absent (path_root substitution propagated)"
fi

# All {__AGT_*__} placeholders consumed (excluding schema + default config).
{
  set +o pipefail
  leftover=$(grep -roE '\{__AGT_[A-Z_]+__\}' "$OUT" 2>/dev/null \
    | grep -vE 'agentify-config\.schema\.json|agentify\.config\.default\.json' \
    | wc -l)
  set -o pipefail
}
if [ "$leftover" = "0" ]; then
  pass "no {__AGT_*__} placeholders remain in rendered output"
else
  ng "$leftover {__AGT_*__} placeholders unconsumed in rendered output"
fi

echo
echo "=== bootstrap smoke: section 3 — install-cache simulation (CLAUDE_PLUGIN_ROOT) ==="
CACHE="$TMP/cache"
mkdir -p "$CACHE"
cp -r "$REPO_ROOT/plugins/agentify/." "$CACHE/"
CACHE_OUT="$TMP/cache-target"
CLAUDE_PLUGIN_ROOT="$CACHE" bash "$CACHE/bin/agentify" \
  --company.name=CacheProbe \
  --skills.prefix=cp \
  --output="$CACHE_OUT" >"$TMP/cache-render.log" 2>&1 \
  || { ng "cache-mode renderer exited non-zero (see $TMP/cache-render.log)"; cat "$TMP/cache-render.log"; }

if [ -f "$CACHE_OUT/AGENTIFY.md" ] && grep -q 'CacheProbe' "$CACHE_OUT/AGENTIFY.md"; then
  pass "cache-mode render produces substituted AGENTIFY.md"
else
  ng "cache-mode render did NOT produce substituted AGENTIFY.md"
fi
if [ -f "$CACHE_OUT/AGENTIFY.md" ] && grep -q '/cp-' "$CACHE_OUT/AGENTIFY.md"; then
  pass "cache-mode skill prefix substituted (/cp-)"
else
  ng "cache-mode skill prefix not substituted"
fi
if [ -f "$CACHE_OUT/.agents-work/AGENTIFY_VERSION" ]; then
  pass "cache-mode AGENTIFY_VERSION marker written"
else
  ng "cache-mode AGENTIFY_VERSION marker missing"
fi

echo
echo "=== bootstrap smoke: section 4 — agentify skill in install-smoke declared list ==="
# install-smoke's declared-skill list (whatever its shape — whitespace-separated
# string, JSON array, jq filter, etc.) must contain the literal token 'agentify'
# as a standalone word so the new T03 entry-skill is exercised by install-smoke.
if grep -E 'declared=.*\bagentify\b' "$REPO_ROOT/bin/test-plugin-install-smoke.sh" >/dev/null \
   || grep -E '"agentify"' "$REPO_ROOT/bin/test-plugin-install-smoke.sh" >/dev/null; then
  pass "test-plugin-install-smoke.sh declares the agentify skill"
else
  ng "test-plugin-install-smoke.sh does NOT declare the agentify skill — install-smoke would miss the new entry-point skill"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "=== bootstrap smoke: HEALTHY (all assertions passed) ==="
  exit 0
else
  echo "=== bootstrap smoke: $fail check(s) failed ==="
  exit 1
fi
