---
description: Detect installed agentify version and migrate to the latest. Subcommands. check — show current + available versions. plan — summarize the relevant migrations/vN.M-to-vX.Y.md. apply — interactive walkthrough; auto-applies non-breaking steps and pauses on breaking ones.
allowed-tools: Read Edit Write Bash
---

# /agt-upgrade

Move an agentified target between agentify versions. Reads `<loop.path_root>/AGENTIFY_VERSION` (or the `AGENTIFY.md` H1 fallback) to detect the current version, then walks through the relevant `migrations/vN.M-to-vX.Y.md` interactively.

## Usage

```
/agt-upgrade check                 # detect current; list available newer versions
/agt-upgrade plan [--to vX.Y]      # summarize the migration doc(s) without applying
/agt-upgrade apply [--to vX.Y] [--dry-run]   # interactive walkthrough
```

Default `--to` is the latest version available in the marketplace's `migrations/` directory.

## Subcommands

### `check`

```bash
plugin_dir="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(realpath "$0")")/../..}"
target_dir="${PWD}"

current=$(bash "$plugin_dir/lib/detect_version.sh" "$target_dir" --quiet)
echo "Current installed version: $current"

available=$(ls "$plugin_dir/../../migrations/" 2>/dev/null \
  | grep -oE 'v[0-9]+\.[0-9]+' | sort -uV | tail -10)
echo "Available migration targets:"
echo "$available" | sed 's/^/  /'

# Suggest the next hop
if [ "$current" != "unknown" ]; then
  next=$(echo "$available" | grep -A1 "^${current}$" | tail -1)
  [ -n "$next" ] && [ "$next" != "$current" ] \
    && echo "Next migration step: $current -> $next" \
    || echo "Already at the latest documented version."
fi
```

### `plan [--to vX.Y]`

Read `migrations/v<current>-to-v<target>.md` and summarize:

- The `## Breaking changes` table (highlight high-impact rows).
- The list of Manual steps (M1, M2, ...) with one-line descriptions.
- The list of Auto-applicable steps (A1, A2, ...) with one-line descriptions.
- The `## Deprecations` table.
- A pointer to the full migration doc.

If multiple hops are needed (e.g., from a much-older version), list all intermediate migration docs and summarize each in order.

### `apply [--to vX.Y] [--dry-run]`

Interactive walkthrough:

1. Run `check` to confirm current version and target.
2. Print the migration's Breaking-changes summary.
3. **Pause** for engineer confirmation: "Proceed with the above breaking changes? (y/N)".
4. For each Manual step (M1, M2, ...): print the step text, pause for engineer to perform it manually + confirm completion.
5. For each Auto-applicable step (A1, A2, ...): print the step text + the commands it will run, pause for engineer confirmation per step, then execute (or print only if `--dry-run`).
6. After all steps complete: write the new version into `<loop.path_root>/AGENTIFY_VERSION` (and append to `<loop.path_root>/UPGRADE_HISTORY` for audit).
7. Run the migration's Verification commands; report PASS/FAIL summary.
8. If verification fails, prompt: "Verification failed; would you like to roll back? (y/N)" — rollback uses `git stash` + `git checkout` of the pre-upgrade tree (no destructive operations).

## Implementation snippets

### Detect + lookup migration

```bash
current=$(bash "$plugin_dir/lib/detect_version.sh" "$target_dir" --quiet)
target_version="${1:-}"  # e.g., "v4.2"; defaults below

if [ -z "$target_version" ]; then
  target_version=$(ls "$plugin_dir/../../migrations/" \
    | grep -oE 'v[0-9]+\.[0-9]+' | sort -uV | tail -1)
fi

migration_doc="$plugin_dir/../../migrations/${current}-to-${target_version}.md"
if [ ! -f "$migration_doc" ]; then
  echo "ERROR: no migration doc at $migration_doc" >&2
  echo "       Multi-hop upgrades may need intermediate migrations." >&2
  exit 1
fi
```

### Apply auto-step (per WS-D-002 template Step An)

```bash
# Each Step An in the migration doc has a ```sh fenced block.
# Extract step An's commands and pipe through bash (with --dry-run echo).
extract_step() {
  local step_id="$1"  # e.g., "A1"
  awk "/^### Step ${step_id}: /,/^### Step |^---/" "$migration_doc" \
    | awk '/^```sh$/,/^```$/' \
    | grep -v '^```'
}

apply_step() {
  local step_id="$1"
  echo "=== Auto-applicable step $step_id ==="
  cmds=$(extract_step "$step_id")
  echo "$cmds" | sed 's/^/  /'
  read -r -p "Apply step $step_id? (y/N) " ans
  case "$ans" in
    y|Y)
      if [ "${dry_run:-0}" -eq 1 ]; then
        echo "[dry-run] would execute the above commands"
      else
        echo "$cmds" | bash
      fi
      ;;
    *)
      echo "Skipped."
      ;;
  esac
}
```

### Update version marker on success

```bash
# After all steps complete, update marker + audit log.
path_root=$(jq -r '.loop.path_root // ".agents-work"' "$target_dir/agentify.config.json" 2>/dev/null)
mkdir -p "$target_dir/$path_root"
echo "$target_version" > "$target_dir/$path_root/AGENTIFY_VERSION"
{
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ): upgraded ${current} -> ${target_version}"
  echo "  applied steps: M1..Mn, A1..An (per migrations/${current}-to-${target_version}.md)"
} >> "$target_dir/$path_root/UPGRADE_HISTORY"
```

## Notes

- **Idempotent.** Re-running `apply` against an already-upgraded target detects via `check` and reports "already at v{TO}; nothing to do".
- **Non-destructive.** Rollback uses `git stash` + `git checkout`; no `git reset --hard` without explicit engineer consent.
- **Multi-hop upgrades.** When several migrations sit between the current and target versions, `apply --to vX.Y` walks them in order, pausing at each version boundary.
- **Synthetic-feedback path.** When `apply` encounters a verification failure that the engineer rolls back, the skill prompts: "Open a feedback issue describing what failed? (y/N)" — on yes, dispatches to `/agt-feedback`.
- **Configuration drift.** If a target's `agentify.config.json` was hand-edited in ways that diverge from the schema, `apply` runs `/agt-config validate` first and refuses to proceed if validation fails (engineer must fix the config first).
