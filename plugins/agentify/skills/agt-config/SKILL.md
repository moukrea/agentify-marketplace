---
description: Inspect and edit the agentify plugin config (project-root agentify.config.json). Subcommands. show — print resolved config. set — update a field. validate — check against agentify-config.schema.json.
allowed-tools: Read Edit Write Bash
---

# /agt-config

Manage the project-root `agentify.config.json` for the agentify plugin. Mirrors the precedence chain implemented by `lib/resolve_config.sh`: skill args > project config > plugin install default > schema defaults.

## Usage

```
/agt-config show                       # print resolved config (all 4 layers merged)
/agt-config show --raw                 # print just project agentify.config.json (no merge)
/agt-config set <field> <value>        # update a single field; <field> is dotted path
/agt-config validate                   # check project config against agentify-config.schema.json
/agt-config init                       # write a starter agentify.config.json from defaults
```

## Subcommands

### `show`

Read the resolved configuration via `lib/resolve_config.sh` and print as pretty JSON:

```bash
bash lib/resolve_config.sh | jq '.'
```

For `--raw`, just `cat agentify.config.json | jq '.'` (or report "no project config" if it doesn't exist).

### `set <field> <value>`

`<field>` is a dotted path like `company.name` or `skills.prefix`. `<value>` is parsed for type (null/true/false/integer/float kept typed; everything else is a string).

Implementation:

```bash
field="$1"
value="$2"
config_file="${AGT_PROJECT_CONFIG:-agentify.config.json}"
# Build jq path: company.name -> .company.name
jq_path=$(printf '%s' "$field" | awk -F. '{ out="."; for (i=1; i<=NF; i++) { if (i>1) out=out"."; out=out $i }; print out }')
# Type the value
case "$value" in
  null) typed='null' ;;
  true) typed='true' ;;
  false) typed='false' ;;
  ''|*[!0-9.-]*) typed=$(jq -R . <<<"$value") ;;
  *) typed="$value" ;;
esac
# Init file if missing
[ -f "$config_file" ] || echo '{}' > "$config_file"
# Apply
jq "$jq_path = $typed" "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"
# Re-validate
/agt-config validate
```

### `validate`

Validate the current `agentify.config.json` against `agentify-config.schema.json`. Two paths:

1. If `ajv` (npm) is available, use it: `ajv validate -s agentify-config.schema.json -d agentify.config.json`.
2. Fallback (no ajv): structural sanity check via jq — required fields present (`company.name`, `skills.prefix`), prefix matches the `^[a-z][a-z0-9]{1,5}$` pattern, no unknown top-level fields. Print a clear PASS or FAIL summary.

Schema location precedence: `agentify-config.schema.json` at repo root > `plugins/agentify/agentify-config.schema.json` (post-WS-C layout).

### `init`

Write a starter `agentify.config.json` populated with the schema defaults plus a TODO comment:

```bash
config_file="${AGT_PROJECT_CONFIG:-agentify.config.json}"
[ -f "$config_file" ] && { echo "ERROR: $config_file already exists; use 'set' to edit"; exit 1; }
# Use the plugin's default file as the seed (drop nulls and clearly-stub values)
jq '.' agentify.config.default.json > "$config_file"
echo "wrote $config_file (edit with 'agt-config set' or via the file directly)"
```

## Notes

- The slash command is registered when this plugin is installed via the marketplace (WS-C).
- The `bash lib/resolve_config.sh` invocation expects `agentify-config.schema.json` and either `agentify.config.json` or `agentify.config.default.json` to be discoverable. Override paths via `AGT_PROJECT_CONFIG` and `AGT_PLUGIN_DEFAULT` env vars when invoking from non-standard locations.
- `set` re-runs `validate` automatically; if validation fails, the previous file is restored (atomic write via `.tmp` move ensures the original is never partially overwritten on a parse failure earlier in the chain).
- This skill is the user-facing surface for the WS-B-003 resolver. For programmatic use (e.g., other skills or scripts), `source lib/resolve_config.sh` and call `agt_resolve_config "$@"` directly.
