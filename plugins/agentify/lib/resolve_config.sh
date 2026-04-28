#!/usr/bin/env bash
# lib/resolve_config.sh — Resolves agentify config from a layered chain.
#
# Precedence (highest first):
#   1. Skill args (parsed from "$@" by agt_parse_args, exported as
#      AGT_ARGS_* env vars).
#   2. Project-root agentify.config.json (path: $AGT_PROJECT_CONFIG, default
#      "$AGT_PROJECT_DIR/agentify.config.json").
#   3. Plugin-install agentify.config.default.json (path: $AGT_PLUGIN_DEFAULT,
#      default "$AGT_PLUGIN_DIR/agentify.config.default.json").
#   4. Hard schema defaults (built into resolve_config.sh).
#
# Outputs the resolved configuration as a single JSON object on stdout.
# Callers can consume it via `jq` or by re-parsing into env vars.
#
# Usage:
#   source lib/resolve_config.sh
#   resolved_json="$(agt_resolve_config --company.name=Acme --skills.prefix=ac)"
#   echo "$resolved_json" | jq -r '.skills.prefix'   # -> ac
#
# Or callable as a script (jq is the only hard dep):
#   bash lib/resolve_config.sh --company.name=Acme --skills.prefix=ac

set -uo pipefail

# Schema-default fallback. Mirrors agentify.config.default.json so the
# resolver still produces a valid config when no files exist (e.g., during
# unit tests in /tmp).
agt_schema_defaults_json() {
  cat <<'EOF'
{
  "company": {"name": "agentify project"},
  "skills": {"prefix": "agt"},
  "plugin": {"name": "agentify", "namespace": "agentify"},
  "marketplace": {
    "name": "agentify-marketplace",
    "url": "https://github.com/moukrea/agentify-marketplace"
  },
  "fleet": {"size_engineers": null},
  "loop": {"path_root": ".agents-work"},
  "ticket_system": {"prefix": "TICKET-"}
}
EOF
}

# Parse skill-style CLI args of form --foo.bar=baz or --foo.bar baz into a
# JSON object that mirrors the dotted-path structure. Echoes the JSON.
# Booleans/numbers are preserved as-typed (null/true/false/123 stay typed,
# everything else is a string).
agt_parse_args_to_json() {
  local args=("$@")
  local i=0
  local pairs=()
  while [ "$i" -lt "${#args[@]}" ]; do
    local arg="${args[$i]}"
    case "$arg" in
      --*=*)
        local key="${arg%%=*}"; key="${key#--}"
        local val="${arg#*=}"
        pairs+=("$key" "$val")
        ;;
      --*)
        local key="${arg#--}"
        local nexti=$((i+1))
        if [ "$nexti" -lt "${#args[@]}" ]; then
          pairs+=("$key" "${args[$nexti]}")
          i=$nexti
        fi
        ;;
      *)
        # Positional args ignored at this layer (consumed by caller).
        :
        ;;
    esac
    i=$((i+1))
  done

  # Build a series of jq setpath expressions, one per pair, applied to {}.
  # Strings, booleans, numbers, and null are typed appropriately.
  local jq_filter='.'
  local k v jpath jval typed_val
  local p=0
  while [ "$p" -lt "${#pairs[@]}" ]; do
    k="${pairs[$p]}"
    v="${pairs[$((p+1))]}"
    # Convert dotted key (a.b.c) into a jq path array string ["a","b","c"]
    # using awk for portability.
    jpath=$(printf '%s' "$k" | awk -F. '{
      out="["
      for (i=1; i<=NF; i++) {
        if (i>1) out=out","
        out=out "\"" $i "\""
      }
      out=out"]"
      print out
    }')
    # Type the value: null/true/false/integer/float stay typed; anything
    # else becomes a JSON string.
    case "$v" in
      null) typed_val='null' ;;
      true) typed_val='true' ;;
      false) typed_val='false' ;;
      ''|*[!0-9.-]*) typed_val=$(jq -R . <<<"$v") ;;
      *) typed_val="$v" ;;
    esac
    jq_filter="${jq_filter} | setpath($jpath; $typed_val)"
    p=$((p+2))
  done
  jq -nc "$jq_filter"
}

# Deep-merge two JSON objects (right wins on conflict; null on right
# REPLACES left). Uses jq's `*` operator with leaf-array preservation.
agt_merge_json() {
  local left="$1"
  local right="$2"
  jq -nc --argjson l "$left" --argjson r "$right" '
    def merge(a; b):
      if (a|type) == "object" and (b|type) == "object" then
        reduce ((a + b) | keys[]) as $k (
          {};
          .[$k] = (
            if (a|has($k)) and (b|has($k)) then merge(a[$k]; b[$k])
            elif (b|has($k)) then b[$k]
            else a[$k]
            end
          )
        )
      else b
      end;
    merge($l; $r)
  '
}

# Main entry point. Accepts skill args as positional parameters.
# Output: resolved JSON config on stdout.
agt_resolve_config() {
  local args=("$@")

  local defaults_json
  defaults_json="$(agt_schema_defaults_json)"

  local plugin_default_path="${AGT_PLUGIN_DEFAULT:-${AGT_PLUGIN_DIR:-}/agentify.config.default.json}"
  local plugin_default_json='{}'
  if [ -f "$plugin_default_path" ]; then
    plugin_default_json="$(jq -c '.' "$plugin_default_path" 2>/dev/null || echo '{}')"
  fi

  local project_config_path="${AGT_PROJECT_CONFIG:-${AGT_PROJECT_DIR:-.}/agentify.config.json}"
  local project_config_json='{}'
  if [ -f "$project_config_path" ]; then
    project_config_json="$(jq -c '.' "$project_config_path" 2>/dev/null || echo '{}')"
  fi

  local skill_args_json='{}'
  if [ "${#args[@]}" -gt 0 ]; then
    skill_args_json="$(agt_parse_args_to_json "${args[@]}")"
  fi

  # Layer in order: defaults < plugin_default < project_config < skill_args.
  local merged
  merged="$(agt_merge_json "$defaults_json" "$plugin_default_json")"
  merged="$(agt_merge_json "$merged" "$project_config_json")"
  merged="$(agt_merge_json "$merged" "$skill_args_json")"
  printf '%s\n' "$merged"
}

# Convenience: get a single dotted-path value from a resolved config.
# Usage: echo "$resolved" | agt_get_config_value skills.prefix
agt_get_config_value() {
  local key="$1"
  local jpath
  jpath=$(printf '%s' "$key" | awk -F. '{
    out="."
    for (i=1; i<=NF; i++) {
      if (i>1) out=out"."
      out=out $i
    }
    print out
  }')
  jq -r "$jpath // empty"
}

# When invoked as a script (not sourced), run agt_resolve_config with all args.
# Detect via BASH_SOURCE[0] vs $0 — when sourced they differ.
if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then
  agt_resolve_config "$@"
fi
