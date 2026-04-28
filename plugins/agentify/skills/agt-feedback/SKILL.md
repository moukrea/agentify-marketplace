---
description: Draft a structured feedback report from a target repo and submit via gh issue create to the configured upstream agentify-marketplace repo. Asks the engineer for the four free-text fields, generates a UUID, presents the body for confirmation, then submits. --dry-run prints the issue body without submitting.
allowed-tools: Read Bash
---

# /agt-feedback

Channel for users of agentified target repos to send structured feedback to the upstream agentify-marketplace. Feedback issues feed into `/agt-self-improve` (WS-F) audits as additional input via `plugins/agentify/lib/feedback_ingest.sh` (WS-G-004).

## Usage

```
/agt-feedback                          # interactive: prompt + confirm + submit
/agt-feedback --dry-run                # build body, print, do not submit
/agt-feedback --label <label>          # add an extra label (e.g., 'p1', 'docs')
/agt-feedback --severity <level>       # pre-fill severity (critical/major/moderate/polish/info)
```

## Algorithm

1. **Resolve upstream repo.** Read `agentify.config.json` for `feedback.upstream_repo`. Falls back to `marketplace.url`'s owner/repo. If neither is set, prompt the engineer for a repo `<owner>/<name>`.
2. **Detect installed version.** `bash plugins/agentify/lib/detect_version.sh . --quiet`. Used to pre-fill the issue body.
3. **Anonymize the target repo profile.** Read `agentify.config.json` for `company.name`, `skills.prefix`, `loop.path_root`, `fleet.size_engineers`. The engineer can override (or anonymize) at confirmation time.
4. **Capture transcript snippet.** Read the last 50 lines of `<loop.path_root>/session-summary.md` (or whichever transcript artifact is available) and pre-fill the Evidence section. Engineer can edit before submit.
5. **Ask the four free-text fields** (via prompts to the engineer):
   - What worked
   - What didn't work
   - Requested change
   - Severity (default `moderate`)
6. **Generate a UUIDv4** for the `agentify-feedback-id` machine-readable footer.
7. **Compose the issue body** by templating the answers into `.github/ISSUE_TEMPLATE/agentify-feedback.md`'s body structure (the engineer reviews the rendered body before submission).
8. **Confirm.** Print the rendered body. Ask: "Submit to <upstream-repo>? (y/N)". On `--dry-run`: skip confirm, just print.
9. **Submit via `gh`.** `gh issue create --repo <upstream-repo> --title "[feedback] <one-liner>" --label agentify-feedback,triage --body-file -`. Pipe the rendered body in via stdin.
10. **Report.** Print the URL of the new issue. Suggest follow-up: "Track via 'gh issue view <#>'; the upstream maintainer's /agt-self-improve will pick this up on the next audit (typically weekly)."

## Implementation snippets

### Resolve upstream repo

```bash
cfg="${AGT_PROJECT_CONFIG:-agentify.config.json}"
upstream_repo=$(jq -r '.feedback.upstream_repo // empty' "$cfg" 2>/dev/null)
if [ -z "$upstream_repo" ]; then
  marketplace_url=$(jq -r '.marketplace.url // empty' "$cfg" 2>/dev/null)
  upstream_repo=$(printf '%s' "$marketplace_url" \
    | sed -E 's|^https?://github\.com/||; s|^github:||; s|\.git$||; s|/$||')
fi
if [ -z "$upstream_repo" ]; then
  echo "ERROR: feedback.upstream_repo not configured. Set via:" >&2
  echo "       /agt-config set feedback.upstream_repo <owner>/<name>" >&2
  exit 2
fi
echo "feedback: upstream_repo=$upstream_repo"
```

### Generate UUID

```bash
new_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  elif [ -r /proc/sys/kernel/random/uuid ]; then
    cat /proc/sys/kernel/random/uuid
  else
    # Fallback: pseudo-uuid from /dev/urandom
    od -An -N16 -tx1 /dev/urandom | tr -d ' \n' \
      | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/'
  fi
}
feedback_id=$(new_uuid)
```

### Compose the issue body

```bash
plugin_root="${CLAUDE_PLUGIN_ROOT:-plugins/agentify}"
template="${plugin_root}/../../.github/ISSUE_TEMPLATE/agentify-feedback.md"

# Strip the YAML frontmatter from the template.
template_body=$(awk 'BEGIN{in_yaml=0} /^---$/{in_yaml=!in_yaml; next} !in_yaml' "$template")

# Substitute fields. Use perl with env-passed values to avoid shell escaping
# headaches with multi-line user input.
export AGT_FB_COMPANY="$company_anon"
export AGT_FB_PREFIX="$skills_prefix"
export AGT_FB_PATH_ROOT="$loop_path_root"
export AGT_FB_FLEET_SIZE="$fleet_size"
export AGT_FB_VERSION="$detected_version"
export AGT_FB_WORKED="$what_worked"
export AGT_FB_BROKEN="$what_didnt_work"
export AGT_FB_REQUESTED="$requested_change"
export AGT_FB_EVIDENCE="$evidence_snippet"
export AGT_FB_ID="$feedback_id"

body=$(printf '%s' "$template_body" \
  | perl -pe 's/\Q{__ANON_COMPANY__}\E/$ENV{AGT_FB_COMPANY}/g;
              s/REPLACE-WITH-UUID/$ENV{AGT_FB_ID}/g;')

# (additional substitutions for other fields would go here; structured-template
# parsing in production would build a dedicated answer renderer)
```

### Submit via gh

```bash
if ! command -v gh >/dev/null 2>&1; then
  echo "WARN: gh CLI not found; printing body for manual paste:" >&2
  printf '%s\n' "$body"
  echo >&2
  echo "Open an issue at: https://github.com/${upstream_repo}/issues/new?template=agentify-feedback" >&2
  exit 0
fi

if [ "${dry_run:-0}" -eq 1 ]; then
  echo "[dry-run] would submit the following body:"
  echo "----"
  printf '%s\n' "$body"
  echo "----"
  echo "[dry-run] gh issue create --repo $upstream_repo --title '[feedback] $one_liner' --label agentify-feedback,triage --body-file -"
  exit 0
fi

read -r -p "Submit to $upstream_repo? (y/N) " ans
case "$ans" in
  y|Y)
    issue_url=$(printf '%s' "$body" | gh issue create \
      --repo "$upstream_repo" \
      --title "[feedback] $one_liner" \
      --label agentify-feedback,triage \
      --body-file -)
    echo "Submitted: $issue_url"
    echo "Track via: gh issue view $(basename "$issue_url")"
    echo "Upstream maintainer's /agt-self-improve will pick this up on the next audit."
    ;;
  *)
    echo "Cancelled."
    exit 0
    ;;
esac
```

## Notes

- **`gh` not required.** If `gh` is missing, the skill prints the issue body and the GitHub URL where the engineer can paste it. This is the fallback per WS-G's risk register.
- **Configurable upstream.** The skill reads `feedback.upstream_repo` from `agentify.config.json` (WS-G-003 extends the schema). Defaults to the marketplace URL's owner/repo when not set explicitly.
- **Anonymization.** The "Target repo profile" block lets the engineer override company name to 'private' or scrub fleet size. The skill never reads or transmits anything outside the configured fields.
- **Two-way feedback loop.** The upstream's `/agt-self-improve` reads open feedback issues via `lib/feedback_ingest.sh` (WS-G-004) and includes them as findings in the next audit. When a finding is addressed (commit lands), the maintainer applies the `addressed` label and closes the issue; the next audit notices the closure and treats the finding as done.
- **Synthetic-feedback path.** `/agt-upgrade apply` (WS-D-004) can dispatch to `/agt-feedback` when an upgrade verification fails, pre-filling the body with the failure diagnostic. Engineers approve the body before submit.
- **No PII.** The template + skill explicitly anonymize the company name when the engineer chooses 'private', and never auto-include unfiltered transcript lines (the engineer reviews before submit).
