# Verification cookbook — static reference

> **No staleness.** This file is reference material that does not depend on Claude Code shipping cycles. The patterns here are conventional and slow-changing.
> **Anchor stability.** Anchor IDs (`{#kebab-case}`) are permanent.

---

## Bash robustness {#bash-robustness}

Standard preamble for every harness-shipped script:

```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# trap on EXIT/INT/TERM for cleanup
cleanup() { :; }
trap cleanup EXIT INT TERM
```

Rules:

- Quote every variable expansion: `"${VAR}"`, `"$@"`, `"${ARRAY[@]}"`. Never bare `$VAR`.
- `${CLAUDE_PROJECT_DIR}` for project-rooted paths in hooks. Defensive default for non-hook invocation:

  ```bash
  CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
  ```

- `realpath` portability — macOS BSD `realpath` lacks `-m` until coreutils is installed:

  ```bash
  resolve_path() {
    if realpath -m / >/dev/null 2>&1; then
      realpath -m "$1"
    else
      python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$1"
    fi
  }
  ```

- `printf '%s\n' "$x"` over `echo -e` for portability across `/bin/sh` variants and Bash builtin echo divergences.
- Use process substitution carefully under `set -e`: `while read … done < <(cmd)` rather than `cmd | while read …` to keep variables in the parent shell.
- For PID-style state files, write with `umask 077` to avoid world-readable session IDs.
- `mktemp` template portability: GNU `mktemp` accepts the full-path template form (`mktemp /path/to/file.tmp.XXXXXX`); BSD `mktemp` (macOS default) is more restrictive. The portable form splits dirname/basename:

  ```bash
  TMP="$(mktemp "${target%/*}/$(basename "$target").tmp.XXXXXX")"
  ```

  Use this form in shared `_lib.sh` `atomic_write_json` and any inline call site. Verified portable across GNU coreutils and BSD `mktemp` (macOS).
- Test multiline pipelines with `set -o pipefail` already in scope; do not assume `cmd1 | cmd2` exits non-zero on `cmd1` failure without it.

---

## JSON validity {#json-validity}

Strict JSON only:

- No trailing commas (`{"a": 1,}` → invalid).
- No comments (`//` or `/* */`).
- No single-quoted strings.
- Unicode escapes use `\uXXXX`.
- Validate with `jq . file.json` before commit.
- For settings.json fragments embedded in prompts, paste through `jq .` once before publishing.

In-script JSON parse / build:

```bash
# parse
session_id=$(jq -r '.session_id // empty' <<<"$HOOK_INPUT")

# build
jq -nc --arg reason "$REASON" '{decision:"block", reason:$reason}'
```

`jq -nc` (null input, compact) is the safe pattern for emitting a single object on stdout for a hook to return.

---

## Conventional Commits regex {#conventional-commits-regex}

Pinned regex (extended POSIX, anchored, used by `prepare-commit-msg`):

```
^(build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test)(\([a-z0-9._\-]+\))?(!)?: [^[:space:]].{0,99}$
```

Three required test subjects (must all PASS):

1. `feat: add user login` — typed commit, no scope.
2. `fix(api)!: drop deprecated endpoint` — typed scoped commit with `!` breaking-change marker.
3. `refactor(parser): split tokenizer` — typed scoped commit, multi-token scope ok.

Body / footer validation runs as a second pass: `BREAKING CHANGE: ...` or `BREAKING-CHANGE: ...` footers permitted; footer tokens hyphenate (`Acked-by`, `Reviewed-by`, `Refs`).

Quick bash test rig:

```bash
re='^(build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test)(\([a-z0-9._\-]+\))?(!)?: [^[:space:]].{0,99}$'
for s in 'feat: add user login' 'fix(api)!: drop deprecated endpoint' 'refactor(parser): split tokenizer'; do
  if [[ "$s" =~ $re ]]; then printf 'PASS  %s\n' "$s"; else printf 'FAIL  %s\n' "$s"; exit 1; fi
done
```

---

## Hook input/output JSON examples {#hook-io-examples}

One block per event AGENTIFY relies on. Cross-checked with https://code.claude.com/docs/en/hooks (fetched 2026-04-27).

### SessionStart

Input:

```json
{
  "session_id": "abc-123",
  "transcript_path": "/.../transcript.jsonl",
  "cwd": "/repo",
  "permission_mode": "default",
  "hook_event_name": "SessionStart"
}
```

Output (inject context for the model):

```json
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Repo: {__AGT_COMPANY_SLUG__}. Loop active: false."
  }
}
```

To persist env vars for later Bash:

```bash
[ -n "${CLAUDE_ENV_FILE:-}" ] && echo 'export EG_LOOP=1' >> "$CLAUDE_ENV_FILE"
```

### PreToolUse

Input adds `tool_name` and `tool_input`. Output to allow with modified input:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "updatedInput": { "command": "git status" },
    "additionalContext": "stripped sudo prefix"
  }
}
```

To deny:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "command touches /etc"
  }
}
```

Decision precedence across multiple matching hooks: `deny > defer > ask > allow`.

### PostToolUse

Input adds `tool_name`, `tool_input`, `tool_response`. Output:

```json
{
  "decision": "block",
  "reason": "lint failed; rerun after fixing src/foo.js"
}
```

Or to inject context without blocking:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "captured plan to .claude/plans/2026-04-27.md"
  }
}
```

### UserPromptSubmit

```json
{
  "decision": "block",
  "reason": "secret-like pattern detected; redact and resubmit",
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "redaction-policy.md applied"
  }
}
```

### Stop

Input:

```json
{
  "session_id": "abc-123",
  "transcript_path": "/.../transcript.jsonl",
  "cwd": "/repo",
  "permission_mode": "default",
  "hook_event_name": "Stop",
  "stop_hook_active": false
}
```

Output to keep the agent looping (Ralph-style):

```json
{
  "decision": "block",
  "reason": "Continue with the next task in TODO.md. Stop only when TODO.md is empty."
}
```

Output to allow exit (default):

```json
{ "continue": true }
```

Always short-circuit at top of script when `stop_hook_active == true` to avoid recursion.

### SubagentStop

Same schema as `Stop`. Input includes `agent_id` and `agent_type`.

### PreCompact

Input includes `trigger` (`auto` or `manual`). Output:

```json
{ "decision": "block", "reason": "compaction unsafe; pin /{__AGT_SKILL_PREFIX__}-status before compacting" }
```

Use `timeout: 30` (seconds). Do NOT set `async: true` on PreCompact; it is synchronous.

---

## Settings JSON shapes {#settings-shapes}

Project `.claude/settings.json` minimum the harness ships:

```json
{
  "permissions": {
    "additionalDirectories": ["../shared-docs"],
    "defaultMode": "default",
    "allow": [],
    "deny": ["Bash(curl http*)", "WebFetch"]
  },
  "plansDirectory": "./plans",
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [
        { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/guard-bash.sh", "timeout": 10 }
      ]}
    ]
  }
}
```

Managed `/etc/claude-code/managed-settings.json`:

```json
{
  "allowManagedHooksOnly": true,
  "allowManagedPermissionRulesOnly": true,
  "strictKnownMarketplaces": [
    { "source": "github", "repo": "{__AGT_COMPANY_SLUG__}/{__AGT_MARKETPLACE_NAME__}" }
  ],
  "permissions": {
    "deny": ["Bash(rm -rf /*)", "Bash(curl * | sh)"]
  }
}
```

Plugin hook config (`<plugin>/hooks/hooks.json`) uses the same `hooks` object shape as `settings.json`.

---

## Smoke-test patterns {#smoke-tests}

Verify hook config is loaded:

```bash
claude --print "/hooks" | grep -F PreToolUse
```

Verify managed-settings allowlist resolves:

```bash
for f in \
  "/etc/claude-code/managed-settings.json" \
  "/Library/Application Support/ClaudeCode/managed-settings.json" \
  "${HOME}/.claude/settings.json" \
  "${HOME}/.claude/settings.local.json" \
  ".claude/settings.json" \
  ".claude/settings.local.json"; do
  [ -f "$f" ] && jq '.permissions.allow // []' "$f" 2>/dev/null
done
```

Portable file-age filter (`find -mmin` is GNU-only):

```bash
age_seconds() {
  python3 -c 'import os,sys,time; print(int(time.time()-os.path.getmtime(sys.argv[1])))' "$1"
}
```

Conventional Commits parser must accept all of: `git commit -m "msg"`, `git commit -m'msg'`, `git commit --message=msg`, `git commit --message msg`, `git commit -F file`, `git commit --file file`. Test each form before shipping.

## Redactor invariants {#redactor-invariants}

A redactor is a function `f: string -> string` that replaces secret-shaped substrings with a marker (e.g. `[REDACTED]`). Four properties must hold; assert all four in any eval harness that exercises a redactor.

1. **Termination (wall-clock bound).** Every call returns within `T` seconds (5 is a reasonable default). Wrap the call in `timeout 5 bash -c '...'`. Catches infinite-loop regressions where the substitution re-matches itself (`while match(s, …)` without progress; awk `[^ \t]+` greedily consuming the marker on the next iteration).
2. **Idempotence.** `f(f(x)) == f(x)`. A second pass over `key: [REDACTED]` must produce the same output. Catches redactors whose replacement is itself matched by the next iteration's regex; catches non-monotonic state.
3. **No-token-survives.** Any token-shaped substring in the input does not appear in the output. The token shape set in this cookbook: `bearer\s+[A-Za-z0-9._-]{16,}`, `sk-[A-Za-z0-9]{20,}`, `ghp_[A-Za-z0-9]{20,}`, `glpat-[A-Za-z0-9_-]{20,}`, `xoxb-[A-Za-z0-9-]{20,}`, `AKIA[0-9A-Z]{16}`, `eyJ[A-Za-z0-9._-]{20,}`. Catches under-matching regressions.
4. **Prose-preservation.** Any substring of the input that does not contain a token shape and is not part of a `key=value` / `key:value` pair with a key in the policy list also appears in the output. Catches over-matching regressions (the canonical example: `_REDACTED.*` greedy strip destroying everything past the first marker).

Recommended implementation language: Python 3 via heredoc. `re.sub` walks left-to-right past each substitution by construction so termination is guaranteed; named capture groups (`(?P<key>…)` / `\g<key>`) preserve original key casing; `(?!\[REDACTED\])` negative lookahead in the value pattern guarantees idempotence. Awk implementations can be made correct (track `RSTART`/`RLENGTH` between iterations and break on no-progress) but the failure modes are subtle and case-fold-then-literal-rewrite normalizes key casing as a side effect.

Caveat on the heredoc form (see `#heredoc-stdin-trap` below): `python3 - <<'PY' … PY` consumes stdin (the heredoc IS the script source). Inside a bash function meant to read from a pipe, this produces empty output. Use `python3 -c '<inline>'` so stdin stays connected to the pipe, OR write the Python to a sibling `.py` file and invoke `python3 path/to/redactor.py` from the bash function.

Last verified: 2026-04-27.

---

## Production-shape smoke {#production-shape-smoke}

The verification command for any function exposed by a hook script must exercise the *deployed call shape*, not an isolated REPL invocation. Three iterations of the agentify loop have stalled because the reviser tested function correctness in the REPL while the deployed code used a different invocation shape (subshell `bash -c`, exported function, stdin pipeline, heredoc semantics, timeout wrapper). The smoke pattern below catches all three iter-5-class regressions in one command.

Canonical one-liner for hook-helper functions called via subshell:

```bash
printf '<synthetic input matching real-traffic shape>\n' | \
  timeout 2 bash -c '. <path-to-hook-script>; <function-name>' | \
  grep -q '<expected-token>' && echo PASS || echo FAIL
```

Worked example for the §12.5 `redact_prose` function called by `replay.sh` and by SessionStart-injected briefings:

```bash
printf 'token=mysecret secret=hunter2 Bearer abcdefghijklmnopqrstuvwxyz\n' | \
  timeout 2 bash -c '. .claude/hooks/session-start-inject.sh; redact_prose' | \
  grep -q '\[REDACTED\]' && echo PASS || echo FAIL
```

The five constraints this enforces:

1. **Production pipeline.** `printf | bash -c` matches how Claude Code pipes hook input through the shell — not how the REPL works. A bare `redact_prose <<<'token=X'` works in the same shell but hides the next four failure modes.
2. **Subshell context.** `bash -c` spawns a fresh shell, so non-exported functions fail `127 = command not found`. Catches the `#bash-function-export` trap.
3. **Function reachability.** Sourcing the script first ensures the function is defined; if the source itself fails (syntax error, missing helper), this catches that too.
4. **Non-empty output.** `grep -q` exits non-zero when stdout is empty. Catches stdin-consumed-by-heredoc bugs (Python `<<'PY'` form, `head -n N` with N=0, etc. — see `#heredoc-stdin-trap`).
5. **Termination.** `timeout 2` exits 124 on hang. Catches infinite loops (awk `gsub` patterns that match `[REDACTED]` and recurse, while-loops with no progress condition, etc.).

Use this exact shape — or a documented variant matching a different deployed call site — in any patch log `**Verification:**` block touching a hook script function. The reviewer's prior-revision cross-check (REVIEW_PROMPT.md) re-executes a sample of these commands; commands that test the wrong call shape are flagged as `caused_by_prior_revise: true` and accelerate the loop's REGRESSION exit.

Last verified: 2026-04-27.

---

## Bash function export across subshells {#bash-function-export}

A function defined or sourced into the parent shell is NOT visible to a child shell unless explicitly exported with `export -f`:

```bash
my_function() { echo "hi from $$"; }
bash -c 'my_function'        # fails 127 = command not found
export -f my_function
bash -c 'my_function'        # succeeds (resolved via BASH_FUNC_my_function%% env var)
```

Hook helper functions called from `bash -c` (e.g., from eval drivers wrapping invocations in `timeout N bash -c '...'`) MUST be `export -f`'d at the bottom of the defining script, with a one-line comment explaining why:

```bash
my_function() {
  : your work
}
# Exported so subshell invocations like `bash -c my_function` (used by
# replay.sh's timeout wrappers and the SessionStart-injected briefing
# pipeline) can resolve it. Without export -f, child shells fail 127
# because non-exported bash functions don't cross subshell boundaries.
export -f my_function
```

This is the C2 anti-pattern from the iter-5 review. Symptom: the function is reachable in the parent shell (manual test passes), invisible from `bash -c` (eval driver fails uniformly with no indication that the function itself is fine, looks like every test case is broken). Cure: `export -f` at function-definition time. Catch: the `#production-shape-smoke` test above invokes via `bash -c` so it surfaces the missing export immediately.

Counter-positive: `__bash_completion__`-style functions or other helpers used only inside the same shell process do not need export. Only export functions called via subshells, eval drivers, or `xargs bash -c` patterns.

Last verified: 2026-04-27.

---

## Heredoc-stdin trap {#heredoc-stdin-trap}

Avoid `python3 - <<EOF ... EOF` (or any `<command> - <<EOF`) inside a bash function meant to consume stdin from a pipe. The heredoc IS the script source for `python3 -`, which means by the time the parsed Python runs `for line in sys.stdin:`, stdin is exhausted (it was the heredoc itself).

Wrong (silent failure — empty output for any pipe input):

```bash
my_function() {
  python3 - <<'PY'
import sys
for line in sys.stdin:
    print(transform(line))
PY
}

echo "data" | my_function    # produces empty output, no error
```

Right (use `python3 -c '<inline>'` so stdin stays available):

```bash
my_function() {
  python3 -c '
import sys
for line in sys.stdin:
    print(transform(line))
'
}

echo "data" | my_function    # produces transformed output
```

Also right (write the script to a sibling `.py` file and invoke it):

```bash
# .claude/hooks/transform.py — script lives on disk
my_function() {
  python3 "$(dirname "${BASH_SOURCE[0]}")/transform.py"
}

echo "data" | my_function    # produces transformed output
```

This is the C1 anti-pattern from the iter-5 review. The bug is silent — exit code is 0, no error printed, just empty stdout — so isolated unit tests (`my_function <<<"data"`) work fine and hide it. The `#production-shape-smoke` test above forces non-empty output via `grep -q` and so catches this.

Generalization: any command that reads its script from `-` or stdin (`sh -`, `awk -f -`, `node -`) consumes the heredoc and breaks the pipeline below. Use the inline-script form (`-c`, `-e`) or write to a file.

Last verified: 2026-04-27.
