#!/usr/bin/env bash
# mkt_self_improve_postflight.sh — invoked by .claude/skills/mkt-self-improve/SKILL.md
# after the audit file is written. Validates PRD 0003 FR-2/3/4/5/7.
#
# Usage: bash mkt_self_improve_postflight.sh <audit-file>
# Exit:  0 on pass; non-zero with stderr explanation on any gate failure.
#
# Gates:
#   FR-2  Audit MUST contain `## Trend findings` heading with >=3 bullets
#         carrying adoption status markers (adopted / partial / not adopted / n/a).
#   FR-3  references[] count MUST be >= max(N_context_urls, N_authority_sources)
#         where N_context_urls = unique URLs in plugins/agentify/context/*.md
#         and N_authority_sources = sources in sources.yaml with authority_weight>=4.
#   FR-4  Postflight re-fetches a 20% sample of references[] URLs (min 3, max 10);
#         refuses if any returns non-2xx OR if the fetched content shares no
#         word with the cited reference's `note` field.
#   FR-5  references[] MUST span >=5 distinct hostnames AND >=2 of those
#         hostnames MUST NOT appear in the curated lists (sources.yaml URLs +
#         plugins/agentify/context/*.md URLs).
#   FR-7  Each new-domain hostname cited in Trend findings MUST have a paired
#         draft ADR at decisions/drafts/draft-add-source-<host-slug>.md.
#
# Refs: PRD 0003 — FR-2, FR-3, FR-4, FR-5, FR-7; ACs 2-6.

set -uo pipefail

audit_file="${1:-}"
if [ -z "$audit_file" ] || [ ! -f "$audit_file" ]; then
	printf 'mkt-self-improve postflight: usage: %s <audit-file>\n' "$0" >&2
	exit 64
fi

REPO_ROOT="${MKT_POSTFLIGHT_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
CONTEXT_DIR="${REPO_ROOT}/plugins/agentify/context"
SOURCES_YAML="${REPO_ROOT}/plugins/agentify/conventions/sources.yaml"
DRAFTS_DIR="${REPO_ROOT}/decisions/drafts"

fail() {
	printf 'postflight FAIL: %s\n' "$1" >&2
	exit 1
}

# Extract the trailing ```json … ``` block from the audit file.
extract_json_block() {
	awk '/^```json[[:space:]]*$/ {flag=1; next} /^```[[:space:]]*$/ {flag=0} flag' "$audit_file"
}

audit_json=$(extract_json_block)
if [ -z "$audit_json" ]; then
	fail "audit file does not contain a fenced \`\`\`json … \`\`\` block (FR-2 prerequisite)"
fi

if ! echo "$audit_json" | jq -e . >/dev/null 2>&1; then
	fail "audit JSON block does not parse as JSON"
fi

# ---------------------------------------------------------------------------
# FR-2 — Trend findings heading + >=3 bulleted patterns with adoption markers.
# ---------------------------------------------------------------------------
if ! grep -qE '^## Trend findings([[:space:]]|$)' "$audit_file"; then
	fail "FR-2: audit is missing the literal '## Trend findings' heading"
fi

# Slice the file between '## Trend findings' and either the next `## ` heading
# OR the start of the trailing fenced JSON block — whichever comes first.
trend_section=$(awk '
	/^## Trend findings([[:space:]]|$)/ {flag=1; next}
	flag && (/^## / || /^```/) {exit}
	flag {print}
' "$audit_file")

# Count bullets that carry an adoption-status marker. Acceptable patterns:
#   - **adopted** ... / - adopted: ...
#   - **partial** / partial:
#   - **not adopted** / not adopted: / not-adopted
#   - **n/a** / n/a:
adoption_count=$(printf '%s\n' "$trend_section" |
	grep -cEi '^[[:space:]]*[-*][[:space:]]+(\*\*)?(adopted|partial|not[[:space:]-]?adopted|n/a)(\*\*)?' || true)

if [ "$adoption_count" -lt 3 ]; then
	fail "FR-2: '## Trend findings' section has only ${adoption_count} adoption-marker bullets; need >=3"
fi

# ---------------------------------------------------------------------------
# FR-3 — references[] count >= dynamic threshold.
# ---------------------------------------------------------------------------
n_context_urls=$(grep -hoE 'https?://[^[:space:])>"]+' "${CONTEXT_DIR}"/*.md 2>/dev/null |
	sort -u | wc -l)
n_authority_sources=0
if [ -f "$SOURCES_YAML" ]; then
	# Each "- id:" with an authority_weight>=4 counts. Cheap awk parser.
	# Portable awk (mawk-compatible): no 3-arg match(); use sub() on a copy.
	n_authority_sources=$(awk '
		BEGIN { in_entry = 0; w = 0; count = 0 }
		/^[[:space:]]*-[[:space:]]+id:/ {
			if (in_entry && w >= 4) count++
			in_entry = 1; w = 0; next
		}
		in_entry && /authority_weight:[[:space:]]*[0-9]+/ {
			line = $0
			sub(/.*authority_weight:[[:space:]]*/, "", line)
			sub(/[^0-9].*/, "", line)
			w = line + 0
		}
		END {
			if (in_entry && w >= 4) count++
			print count + 0
		}
	' "$SOURCES_YAML")
fi

threshold=$(( n_context_urls > n_authority_sources ? n_context_urls : n_authority_sources ))
if [ "$threshold" -lt 1 ]; then
	threshold=1
fi

refs_count=$(echo "$audit_json" | jq -r '[.findings[].references[]] | length')

if [ "$refs_count" -lt "$threshold" ]; then
	fail "FR-3: references[] count=${refs_count} < threshold=${threshold} (max of context-URLs=${n_context_urls}, authority-sources=${n_authority_sources})"
fi

# ---------------------------------------------------------------------------
# FR-5 — diversity: >=5 distinct hostnames; >=2 outside curated lists.
# ---------------------------------------------------------------------------
mapfile -t ref_urls < <(echo "$audit_json" | jq -r '[.findings[].references[].url] | unique[]')

extract_host() {
	local url="$1"
	# Strip scheme://, then take up to the next / or :
	local host="${url#*://}"
	host="${host%%/*}"
	host="${host%%:*}"
	printf '%s\n' "$host"
}

declare -A ref_hosts=()
for url in "${ref_urls[@]:-}"; do
	[ -n "$url" ] || continue
	host=$(extract_host "$url")
	ref_hosts["$host"]=1
done

distinct_host_count="${#ref_hosts[@]}"
if [ "$distinct_host_count" -lt 5 ]; then
	fail "FR-5: only ${distinct_host_count} distinct hostnames in references[]; need >=5"
fi

# Curated host list = sources.yaml URLs + context/*.md URLs.
mapfile -t curated_urls < <(
	{
		grep -hoE 'https?://[^[:space:])>"]+' "$SOURCES_YAML" 2>/dev/null || true
		grep -hoE 'https?://[^[:space:])>"]+' "${CONTEXT_DIR}"/*.md 2>/dev/null || true
	} | sort -u
)
declare -A curated_hosts=()
for url in "${curated_urls[@]:-}"; do
	[ -n "$url" ] || continue
	curated_hosts["$(extract_host "$url")"]=1
done

out_of_list_count=0
out_of_list_hosts=()
for host in "${!ref_hosts[@]}"; do
	if [ -z "${curated_hosts[$host]:-}" ]; then
		out_of_list_count=$((out_of_list_count + 1))
		out_of_list_hosts+=("$host")
	fi
done

if [ "$out_of_list_count" -lt 2 ]; then
	fail "FR-5: only ${out_of_list_count} reference hostname(s) outside curated lists; need >=2 (forces real discovery)"
fi

# ---------------------------------------------------------------------------
# FR-7 — each new-domain hostname cited in Trend findings MUST have a draft ADR.
# ---------------------------------------------------------------------------
mkdir -p "$DRAFTS_DIR"
# Hostnames mentioned in the trend section's URLs.
trend_hosts=()
while IFS= read -r url; do
	[ -n "$url" ] || continue
	trend_hosts+=("$(extract_host "$url")")
done < <(printf '%s' "$trend_section" | grep -oE 'https?://[^[:space:])>"]+' | sort -u)

host_slug() {
	# Convert hostname to a filename-safe slug: lowercase, dots → dashes.
	printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr '.' '-'
}

missing_drafts=()
for host in "${trend_hosts[@]:-}"; do
	[ -n "$host" ] || continue
	if [ -z "${curated_hosts[$host]:-}" ]; then
		slug=$(host_slug "$host")
		draft="${DRAFTS_DIR}/draft-add-source-${slug}.md"
		if [ ! -f "$draft" ]; then
			missing_drafts+=("$host -> $draft")
		fi
	fi
done

if [ "${#missing_drafts[@]}" -gt 0 ]; then
	{
		printf 'FR-7: %d new-domain hostname(s) in Trend findings lack a paired draft ADR:\n' "${#missing_drafts[@]}"
		for entry in "${missing_drafts[@]}"; do
			printf '  - %s\n' "$entry"
		done
		printf 'Generate via plugins/agentify/templates/lifecycle/add-source-adr.md.template\n'
	} >&2
	exit 1
fi

# ---------------------------------------------------------------------------
# FR-4 — re-fetch a 20% sample of references[]; refuse on non-2xx or
# content-mismatch.
# ---------------------------------------------------------------------------
sample_size=$(( refs_count / 5 ))
[ "$sample_size" -lt 3 ] && sample_size=3
[ "$sample_size" -gt 10 ] && sample_size=10
[ "$sample_size" -gt "$refs_count" ] && sample_size="$refs_count"

# Deterministic sample: sort refs by url, pick every (refs_count/sample_size)th.
mapfile -t sorted_refs < <(echo "$audit_json" |
	jq -c '[.findings[].references[]] | sort_by(.url) | .[]')

step=$(( refs_count / sample_size ))
[ "$step" -lt 1 ] && step=1

i=0
sample_idx=0
fetch_failures=()
for entry in "${sorted_refs[@]}"; do
	if [ $(( i % step )) -eq 0 ] && [ "$sample_idx" -lt "$sample_size" ]; then
		url=$(echo "$entry" | jq -r '.url')
		note=$(echo "$entry" | jq -r '.note // ""')

		# Cache-check: skip if we've fetched this URL within the last hour.
		cache_dir="/tmp/mkt-postflight-cache"
		mkdir -p "$cache_dir"
		url_sha=$(printf '%s' "$url" | sha256sum | cut -c1-16)
		cache_file="${cache_dir}/${url_sha}"
		if [ ! -f "$cache_file" ] || [ "$(find "$cache_file" -mmin +60 2>/dev/null)" = "$cache_file" ]; then
			# (Re-)fetch.
			http_code=$(curl -sSL -o "$cache_file" -w '%{http_code}' --max-time 15 \
				-A "agentify-mkt-postflight/1.0" "$url" 2>/dev/null) || http_code="000"
			if [[ ! "$http_code" =~ ^2[0-9][0-9]$ ]]; then
				fetch_failures+=("$url -> HTTP ${http_code}")
				sample_idx=$((sample_idx + 1))
				i=$((i + 1))
				continue
			fi
		fi

		# Content sanity check: if `note` is non-trivial, ensure at least one
		# word from the note (length>=4) appears in the fetched content.
		if [ -n "$note" ]; then
			matched=0
			# Pick up to 5 substantive words from the note.
			read -ra note_words < <(printf '%s' "$note" |
				tr -c '[:alnum:]_' ' ' |
				tr -s ' ' |
				tr '[:upper:]' '[:lower:]')
			checked=0
			for word in "${note_words[@]:-}"; do
				if [ "${#word}" -ge 4 ] && [ "$checked" -lt 5 ]; then
					checked=$((checked + 1))
					if grep -qiF -- "$word" "$cache_file" 2>/dev/null; then
						matched=1
						break
					fi
				fi
			done
			if [ "$checked" -gt 0 ] && [ "$matched" -eq 0 ]; then
				fetch_failures+=("$url -> content does not contain any cited keyword (checked ${checked} words from note)")
			fi
		fi

		sample_idx=$((sample_idx + 1))
	fi
	i=$((i + 1))
done

if [ "${#fetch_failures[@]}" -gt 0 ]; then
	{
		printf 'FR-4: %d reference(s) failed re-fetch verification:\n' "${#fetch_failures[@]}"
		for entry in "${fetch_failures[@]}"; do
			printf '  - %s\n' "$entry"
		done
	} >&2
	exit 1
fi

# All gates passed.
printf 'postflight OK: %s (refs=%d/%d, hosts=%d, out-of-list=%d, trend-adoption-bullets=%d, fetched-sample=%d)\n' \
	"$audit_file" "$refs_count" "$threshold" \
	"$distinct_host_count" "$out_of_list_count" "$adoption_count" "$sample_idx" >&2
exit 0
