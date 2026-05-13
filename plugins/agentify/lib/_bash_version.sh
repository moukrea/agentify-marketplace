#!/usr/bin/env bash
# plugins/agentify/lib/_bash_version.sh — central bash-version guard.
#
# Several scripts and drivers in the marketplace use bash 4+ features:
#   * `declare -A` (associative arrays)
#   * `${!ref-}` (indirect parameter expansion)
#   * `mapfile` / `readarray`
#   * `${var,,}` lower-case parameter expansion
#
# macOS still ships bash 3.2 by default. Contributors on macOS should
# install Homebrew bash (`brew install bash`) and ensure it's first on
# PATH so the shebangs resolve correctly. CI runs on ubuntu-24.04 with
# bash 5.x.
#
# Source this file from any script that uses bash 4+ features:
#   . "$(dirname "${BASH_SOURCE[0]}")/_bash_version.sh"
#
# Exit code 78 (EX_CONFIG) signals "configuration mismatch the user
# must fix locally" rather than a script bug.

if [ -z "${BASH_VERSINFO+set}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
	echo "agentify: this script requires bash 4+ (current: ${BASH_VERSION:-unknown})" >&2
	echo "  install via Homebrew on macOS:  brew install bash" >&2
	echo "  ensure it's first on PATH so the shebang resolves it." >&2
	exit 78
fi
