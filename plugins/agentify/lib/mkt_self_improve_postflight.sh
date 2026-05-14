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
# FR-7 (rewritten in v6.0 PRD 0004) — accumulation-based discovery.
#
# Old v5.0 behaviour: every new-domain hostname cited in Trend findings
# MUST have a paired draft ADR. Result: per-citation friction discouraged
# discovery. The model gravitated toward re-citing known sources.
#
# New v6.0 behaviour: extract new-domain citations, append each to
# `plugins/agentify/practices/discovered-sources.jsonl` (under flock for
# concurrency safety), count distinct audit-ids per domain across the
# accumulated log, and require a draft ADR ONLY for domains that have
# crossed the configurable threshold N (default 3). Pre-threshold
# citations are silent — discovery is free.
# ---------------------------------------------------------------------------
mkdir -p "$DRAFTS_DIR"
DISCOVERED_LOG="${REPO_ROOT}/plugins/agentify/practices/discovered-sources.jsonl"
mkdir -p "$(dirname "$DISCOVERED_LOG")"
[ -f "$DISCOVERED_LOG" ] || printf '# accumulation log\n' >"$DISCOVERED_LOG"

# Threshold from agentify.config.json:.self_improve.discovery_threshold,
# default 3, minimum 2 (per agentify-config.schema.json).
DISCOVERY_THRESHOLD=3
config_file="${REPO_ROOT}/agentify.config.json"
if [ -f "$config_file" ]; then
	cfg_val=$(jq -r '.self_improve.discovery_threshold // empty' "$config_file" 2>/dev/null) || cfg_val=""
	if [ -n "$cfg_val" ] && [[ "$cfg_val" =~ ^[0-9]+$ ]] && [ "$cfg_val" -ge 2 ]; then
		DISCOVERY_THRESHOLD="$cfg_val"
	fi
fi

# Extract audit_id from the audit JSON block.
audit_id=$(echo "$audit_json" | jq -r '.audit_id')
audit_ts=$(echo "$audit_json" | jq -r '.produced_at // "1970-01-01T00:00:00Z"')

host_slug() {
	# Convert hostname to a filename-safe slug: lowercase, dots → dashes.
	printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr '.' '-'
}

# Hostnames mentioned in the trend section's URLs.
trend_hosts=()
trend_urls=()
while IFS= read -r url; do
	[ -n "$url" ] || continue
	trend_hosts+=("$(extract_host "$url")")
	trend_urls+=("$url")
done < <(printf '%s' "$trend_section" | grep -oE 'https?://[^[:space:])>"]+' | sort -u)

# Append new-domain citations to the accumulation log (under flock).
# Each line is a self-contained JSON object; the file is the discovery trail.
i=0
for host in "${trend_hosts[@]:-}"; do
	[ -n "$host" ] || { i=$((i + 1)); continue; }
	if [ -z "${curated_hosts[$host]:-}" ]; then
		# Extract a short context quote: 80 chars around the first occurrence.
		quote=$(printf '%s' "$trend_section" | grep -F "${trend_urls[$i]}" | head -1 | tr -s '[:space:]' ' ' | cut -c1-160)
		(
			flock -x 9
			jq -nc \
				--arg domain "$host" \
				--arg audit_id "$audit_id" \
				--arg quote "$quote" \
				--arg url "${trend_urls[$i]}" \
				--arg ts "$audit_ts" \
				'{domain:$domain, audit_id:$audit_id, trend_context_quote:$quote, ref_url:$url, ts:$ts}' \
				>>"$DISCOVERED_LOG"
		) 9>>"$DISCOVERED_LOG"
	fi
	i=$((i + 1))
done

# Count distinct audit-ids per domain in the accumulation log.
# Threshold check: any domain with >= DISCOVERY_THRESHOLD distinct citations
# triggers AUTO-GENERATION of a draft ADR (if missing). Postflight then PASSES
# — the discovery accumulation is the gate; the draft ADR is the artifact for
# maintainer review.
# Template lives in the plugin source (next to this script's lib/), not in
# the consuming repo (REPO_ROOT may differ in tests / tenant installs).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADR_TEMPLATE="${SCRIPT_DIR}/../templates/lifecycle/add-source-adr.md.template"
declare -A counted_for_host=()
generated_drafts=()
while IFS= read -r line; do
	# Skip comment + empty lines.
	[[ "$line" =~ ^#|^[[:space:]]*$ ]] && continue
	host=$(printf '%s' "$line" | jq -r '.domain // empty' 2>/dev/null) || continue
	[ -z "$host" ] && continue
	[ -n "${counted_for_host[$host]:-}" ] && continue
	# Count distinct audit_ids for this host.
	count=$(grep -F "\"domain\":\"$host\"" "$DISCOVERED_LOG" 2>/dev/null |
		jq -r '.audit_id' 2>/dev/null | sort -u | wc -l)
	if [ "$count" -ge "$DISCOVERY_THRESHOLD" ]; then
		slug=$(host_slug "$host")
		draft="${DRAFTS_DIR}/draft-add-source-${slug}.md"
		if [ ! -f "$draft" ] && [ -f "$ADR_TEMPLATE" ]; then
			# Auto-generate the draft from the template.
			# Pull the most recent JSONL entry for this host for context.
			first_entry=$(grep -F "\"domain\":\"$host\"" "$DISCOVERED_LOG" 2>/dev/null | tail -1)
			first_url=$(printf '%s' "$first_entry" | jq -r '.ref_url')
			first_quote=$(printf '%s' "$first_entry" | jq -r '.trend_context_quote')
			first_ts=$(printf '%s' "$first_entry" | jq -r '.ts')
			sed \
				-e "s|__HOSTNAME__|$host|g" \
				-e "s|__URL__|$first_url|g" \
				-e "s|__TREND_QUOTE__|$first_quote|g" \
				-e "s|__RECOMMENDED_AUTHORITY_WEIGHT__|3|g" \
				-e "s|__RECOMMENDED_ID__|$slug|g" \
				-e "s|__GENERATED_AT__|$(date -u +%Y-%m-%dT%H:%M:%SZ)|g" \
				-e "s|__AUDIT_DATE__|${audit_id:0:8}|g" \
				-e "s|__AUDIT_ID__|$audit_id|g" \
				"$ADR_TEMPLATE" >"$draft"
			generated_drafts+=("$host -> $draft (count=$count crossed threshold=$DISCOVERY_THRESHOLD)")
		fi
	fi
	counted_for_host["$host"]=1
done <"$DISCOVERED_LOG"

if [ "${#generated_drafts[@]}" -gt 0 ]; then
	{
		printf 'FR-7 (v6.0 accumulation): %d new-domain hostname(s) crossed threshold; draft ADRs auto-generated for maintainer review:\n' "${#generated_drafts[@]}"
		for entry in "${generated_drafts[@]}"; do
			printf '  - %s\n' "$entry"
		done
		printf 'Drafts live under decisions/drafts/. Review and either move to decisions/<NNNN>-...md (accept) or delete (reject).\n'
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
