#!/usr/bin/env bash
# plugins/agentify/bin/onboard.sh
# Once-per-engineer marketplace registration + plugin install for the
# {__AGT_PLUGIN_NAME__} plugin. Workaround for issues #16870 / #32606 /
# #13096 (extraKnownMarketplaces does not auto-register from managed
# settings, project settings, or headless mode).
#
# Two execution modes:
#   - Plugin-embedded (default): placeholders {__AGT_*__} are
#     substituted by the agentification entry script when the plugin
#     is rendered into a target repo. Engineers in the target run
#     this from scripts/onboard.sh after agentification.
#   - Marketplace-direct: engineers can also fetch this script from
#     the marketplace repo and run it with env vars overriding the
#     placeholders to install the plugin into Claude Code without
#     going through a target repo first. Useful for try-before-bootstrap.
#
# Usage:
#   bash onboard.sh                    # apply (register + install)
#   bash onboard.sh --dry-run          # print what would happen, no execution
#   MARKETPLACE_URL=... PLUGIN=... bash onboard.sh   # override defaults
#
# Exit 0 on success or --dry-run; non-zero on any failure.

set -euo pipefail

dry_run=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) dry_run=1 ;;
    --help|-h)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
  esac
done

# Defaults from agentification-time placeholders (left bare in the
# marketplace repo so dry-run works without resolution; substituted by
# bin/agentify when the plugin is rendered into a target). Engineers
# can also export these env vars to run the marketplace-direct flow.
#
# Note: placeholders live in their own variables (not inlined into the
# parameter expansion default) because the closing `}` of the
# placeholder would otherwise collide with bash's `${VAR:-default}`
# parser and produce a stray `}` in the resolved value.
DEFAULT_MARKETPLACE_URL='{__AGT_MARKETPLACE_URL__}'
DEFAULT_MARKETPLACE_NAME='{__AGT_MARKETPLACE_NAME__}'
DEFAULT_PLUGIN_NAME='{__AGT_PLUGIN_NAME__}'

MARKETPLACE_URL="${MARKETPLACE_URL:-$DEFAULT_MARKETPLACE_URL}"
MARKETPLACE_NAME="${MARKETPLACE_NAME:-$DEFAULT_MARKETPLACE_NAME}"
PLUGIN_NAME="${PLUGIN_NAME:-$DEFAULT_PLUGIN_NAME}"
PLUGIN="${PLUGIN:-${PLUGIN_NAME}@${MARKETPLACE_NAME}}"
PINNED_VERSION="${PINNED_VERSION:-}"

run() {
  if [ "$dry_run" -eq 1 ]; then
    echo "[dry-run] would run: $*"
  else
    "$@"
  fi
}

# Detect whether `claude plugin` is the bare CLI form or slash-only.
detect_form() {
  if [ "$dry_run" -eq 1 ] && ! command -v claude >/dev/null 2>&1; then
    # Dry-run without claude: assume bare form for output formatting.
    echo "bare"
    return
  fi
  if claude plugin --help >/dev/null 2>&1; then
    echo "bare"
  else
    echo "slash"
  fi
}

if [ "$dry_run" -ne 1 ] && ! command -v claude >/dev/null 2>&1; then
  echo "onboard: claude CLI not found on PATH. Install Claude Code first." >&2
  exit 1
fi

CLI_FORM="$(detect_form)"

list_marketplaces() {
  case "$CLI_FORM" in
    bare)  claude plugin marketplace list 2>/dev/null ;;
    slash) claude --print "/plugin marketplace list" 2>/dev/null ;;
  esac
}
add_marketplace() {
  case "$CLI_FORM" in
    bare)  run claude plugin marketplace add "$1" ;;
    slash) run claude --print "/plugin marketplace add $1" ;;
  esac
}
list_plugins() {
  case "$CLI_FORM" in
    bare)  claude plugin list 2>/dev/null ;;
    slash) claude --print "/plugin list" 2>/dev/null ;;
  esac
}
install_plugin() {
  case "$CLI_FORM" in
    bare)  run claude plugin install "$1" ;;
    slash) run claude --print "/plugin install $1" ;;
  esac
}

echo "onboard: marketplace=${MARKETPLACE_NAME} url=${MARKETPLACE_URL}"
echo "onboard: plugin=${PLUGIN} (CLI form: ${CLI_FORM})"

if [ "$dry_run" -eq 1 ] || ! list_marketplaces | grep -q "$MARKETPLACE_NAME"; then
  echo "onboard: registering marketplace $MARKETPLACE_NAME"
  add_marketplace "$MARKETPLACE_URL"
else
  echo "onboard: marketplace $MARKETPLACE_NAME already registered"
fi

INSTALL_TARGET="$PLUGIN"
[ -n "$PINNED_VERSION" ] && INSTALL_TARGET="${PLUGIN}@${PINNED_VERSION}"

if [ "$dry_run" -eq 1 ] || ! list_plugins | grep -q "$PLUGIN_NAME"; then
  echo "onboard: installing $INSTALL_TARGET"
  install_plugin "$INSTALL_TARGET"
else
  echo "onboard: $PLUGIN_NAME already installed"
fi

echo "onboard: complete. Verify with: claude plugin list && claude /hooks"
