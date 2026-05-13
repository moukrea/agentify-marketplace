#!/usr/bin/env bash
# plugins/agentify/lib/_io.sh — shared I/O + safety primitives.
#
# Six helpers + four symbolic exit codes consumed by every dispatcher,
# driver, hook, and bin/ script in the marketplace. Sourcing _io.sh
# implicitly sources _bash_version.sh, so any file that needs bash 4+
# can `. _io.sh` instead of carrying its own version guard.
#
# Functions:
#   atomic_write          <dest> <cmd...>
#   validate_driver_name  <name> <context>
#   curl_with_token       <method> <base> <path> <token-var-name> [extra...]
#   grep_outside_fences   <pattern> <file>
#   _warn                 <msg...>
#   _die                  <code> <msg...>
#
# Exit-code constants (BSD sysexits.h convention; matches _bash_version.sh):
#   EX_USAGE       = 64    command-line usage error
#   EX_DATAERR     = 65    data format error
#   EX_UNAVAILABLE = 69    service unavailable (missing CLI / closed network)
#   EX_CONFIG      = 78    configuration error (also used by _bash_version.sh)

# Double-source guard. _io.sh is sourced from many drivers; idempotent
# is required so the bash-version probe runs at most once per process.
[ -n "${__AGT_IO_SH_SOURCED:-}" ] && return 0
__AGT_IO_SH_SOURCED=1

# shellcheck source=_bash_version.sh
. "$(dirname "${BASH_SOURCE[0]}")/_bash_version.sh"

# Symbolic exit codes. Exported so subshells (jq -n filters, awk
# helpers, mock CLIs) see them. Values match BSD sysexits.h.
export EX_USAGE=64
export EX_DATAERR=65
export EX_UNAVAILABLE=69
export EX_CONFIG=78

# _warn <msg...> — print to stderr, always return 0.
# Use to surface non-fatal diagnostics without short-circuiting `set -e`.
_warn() {
	printf '%s\n' "$*" >&2 || true
	return 0
}

# _die <code> <msg...> — print to stderr, exit with <code>.
# Use for terminal errors at the top of a function:
#     [ -z "$ref" ] && _die "$EX_USAGE" "task_create: ref required"
_die() {
	local code="${1:-1}"
	shift
	printf '%s\n' "$*" >&2
	exit "$code"
}

# atomic_write <dest> <cmd...> — run cmd; capture stdout into a
# tempfile next to <dest>; chmod 600; mv into place. If cmd exits
# non-zero, the tempfile is removed and <dest> is unchanged.
#
# Promoted from hooks/_lib.sh:atomic_write_json. Identical contract
# (same signature, same atomicity guarantees). The original is now a
# thin wrapper that calls through.
#
# Restores the caller's umask on exit (the original `atomic_write_json`
# leaked umask 077 to subsequent commands in the same shell).
atomic_write() {
	local target="${1:-}"; shift || return "$EX_USAGE"
	[ -z "$target" ] && { _warn "atomic_write: missing target"; return "$EX_USAGE"; }
	local dir base tmp oldumask rc
	dir="${target%/*}"
	[ "$dir" = "$target" ] && dir=.
	base="$(basename -- "$target")"
	oldumask=$(umask)
	umask 077
	# Portable mktemp template form: suffix at the end of the basename.
	# Same-FS placement so the final `mv` is atomic.
	tmp="$(mktemp "${dir}/${base}.tmp.XXXXXX")" || {
		umask "$oldumask"
		return 1
	}
	umask "$oldumask"
	if "$@" >"$tmp"; then
		chmod 600 "$tmp" 2>/dev/null || true
		mv "$tmp" "$target"
	else
		rc=$?
		rm -f "$tmp"
		return "$rc"
	fi
}

# validate_driver_name <name> <context> — exit EX_USAGE if name has
# path-traversal characters or violates the canonical regex.
#
# Allowed regex: ^[a-z0-9][a-z0-9_-]*$
# Rejected: empty, leading dot, contains `/`, contains `..`, contains
# uppercase, contains shell metachars.
#
# Called from every driver-loading dispatcher (secrets.sh, git_host.sh,
# task_backend.sh, fleet_discover.sh) BEFORE the driver file is
# sourced, so a hostile config cannot smuggle in arbitrary code via a
# driver name like `../../etc/passwd`.
validate_driver_name() {
	local name="${1:-}" context="${2:-driver}" quoted
	quoted="$(printf '%q' "$name")"
	case "$name" in
		""|*/*|*..*|.*)
			_die "$EX_USAGE" "${context}: invalid driver name ${quoted} (must match ^[a-z0-9][a-z0-9_-]*\$)"
			;;
	esac
	if ! [[ "$name" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
		_die "$EX_USAGE" "${context}: invalid driver name ${quoted} (must match ^[a-z0-9][a-z0-9_-]*\$)"
	fi
}

# curl_with_token <method> <base> <path> <token-var-name> [extra-curl-args...]
#
# Run a curl request whose Authorization header is sourced from the
# env var named by <token-var-name>. The header is written to a
# mktemp config file (curl -K form) so the token never appears in
# argv, `/proc/<pid>/cmdline`, or `bash -x` xtrace output.
#
# Auth format defaults to "Authorization: Bearer %s" where %s is the
# token. Override per-driver via AGT_CURL_AUTH_HEADER_FMT:
#     AGT_CURL_AUTH_HEADER_FMT='PRIVATE-TOKEN: %s' curl_with_token \
#         GET https://gitlab.com /api/v4/projects GITLAB_TOKEN
#
# Robustness:
#   - Disables xtrace while writing the secret file (so `bash -x` of the
#     dispatcher doesn't leak the token via printf argv tracing).
#   - umask 077 + chmod 600 on the cfg file.
#   - Probes for --fail-with-body (curl ≥ 7.76); falls back to --fail
#     on older curl with a stderr _warn.
#   - RETURN trap removes the cfg file on normal function exit.
#   - --max-time 30 bounds the SIGINT-interruption window (cfg file
#     may briefly remain in $TMPDIR if curl is killed mid-flight; the
#     trap fires for normal exits including curl non-zero return).
#
# Returns curl's exit code.
curl_with_token() {
	local method="${1:-GET}" base="${2:-}" path="${3:-}" tokvar="${4:-}"
	if [ "$#" -lt 4 ]; then
		_warn "curl_with_token: need <method> <base> <path> <token-var-name>"
		return "$EX_USAGE"
	fi
	shift 4
	[ -z "$tokvar" ] && { _warn "curl_with_token: token-var-name is empty"; return "$EX_USAGE"; }

	# Disable xtrace BEFORE the indirect expansion that binds $token,
	# otherwise `bash -x` of the dispatcher captures the secret as the
	# value of the `local token=…` trace line. Re-enable on every exit
	# path (including the error returns below).
	local xtrace_was_on=0
	case $- in *x*) xtrace_was_on=1 ;; esac
	{ set +x; } 2>/dev/null

	# Indirect expansion (bash 4+; guarded by _bash_version.sh source).
	local token="${!tokvar:-}"
	if [ -z "$token" ]; then
		[ "$xtrace_was_on" = 1 ] && set -x
		_warn "curl_with_token: env var ${tokvar} is empty"
		return "$EX_CONFIG"
	fi
	local fmt="${AGT_CURL_AUTH_HEADER_FMT:-Authorization: Bearer %s}"

	# Probe --fail-with-body (curl ≥ 7.76). RHEL 8 ships 7.61.
	local fail_flag="--fail"
	if curl --help all 2>/dev/null | grep -q -- --fail-with-body; then
		fail_flag="--fail-with-body"
	fi

	# Build the cfg file. umask 077 + chmod 600 protect on disk.
	local cfg oldumask
	oldumask=$(umask)
	umask 077
	if ! cfg="$(mktemp 2>/dev/null)"; then
		umask "$oldumask"
		[ "$xtrace_was_on" = 1 ] && set -x
		_warn "curl_with_token: mktemp failed"
		return 1
	fi
	umask "$oldumask"
	chmod 600 "$cfg" 2>/dev/null || true
	# shellcheck disable=SC2059
	printf "header = \"${fmt}\"\n" "$token" >"$cfg"

	# Re-enable xtrace AFTER the secret has been written + the printf
	# argv has been consumed. The curl line that follows is safe to
	# trace: the token only appears in the cfg file (loaded via -K),
	# never on argv or in the trace.
	[ "$xtrace_was_on" = 1 ] && set -x

	# Cleanup on RETURN. (Signal interruption leaves the file briefly;
	# --max-time bounds the window.)
	# shellcheck disable=SC2064
	trap "rm -f '$cfg'" RETURN

	curl -sS "$fail_flag" --max-time 30 -K "$cfg" -X "$method" "${base%/}/${path#/}" "$@"
}

# grep_outside_fences <pattern> <file> — emit "LINENO:CONTENT" for
# every line in <file> matching <pattern> that is NOT inside a fenced
# code block (lines bounded by ``` markers). Used by:
#   - bin/validate-migration.sh leftover-placeholder check
#   - lifecycle-conformance task-count gate
#   - markdown driver's per-phase Validation rule
#
# Returns 0 if any match, 1 otherwise.
grep_outside_fences() {
	local pattern="${1:-}" file="${2:-}"
	if [ -z "$pattern" ] || [ -z "$file" ]; then
		_warn "grep_outside_fences: need <pattern> <file>"
		return "$EX_USAGE"
	fi
	if [ ! -f "$file" ]; then
		_warn "grep_outside_fences: ${file} not found"
		return "$EX_DATAERR"
	fi
	awk -v pat="$pattern" '
		BEGIN { in_fence = 0; matched = 0 }
		/^```/ { in_fence = !in_fence; next }
		!in_fence && $0 ~ pat { printf "%d:%s\n", NR, $0; matched = 1 }
		END { exit (matched ? 0 : 1) }
	' "$file"
}
