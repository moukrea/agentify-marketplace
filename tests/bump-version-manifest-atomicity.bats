#!/usr/bin/env bats
# tests/bump-version-manifest-atomicity.bats — regression net for B-3.
#
# bin/bump-version.sh updates plugin.json + marketplace.json in lockstep.
# Before B-3 fix, the writes were two sequential `mv` calls with no
# rollback: if the second failed, plugin.json was already overwritten
# but marketplace.json stayed at the old version. The fix snapshots
# both manifests to .bak files, installs an EXIT/INT/TERM/HUP trap
# that restores on any abnormal exit, and disarms the trap only after
# both mvs succeed.
#
# This bats injects a fault into the second jq invocation (via a
# mocked jq on PATH) and asserts both manifests revert to their
# pre-call sha256.

bats_require_minimum_version 1.5.0

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
	SANDBOX="$(mktemp -d)"
	cd "$SANDBOX"
	git init -q --initial-branch=main >/dev/null
	git config user.email "tester@agentify.test"
	git config user.name "Tester"
	git config commit.gpgsign false

	# Seed manifests at v4.3.0
	mkdir -p plugins/agentify/.claude-plugin .claude-plugin plugins/agentify/migrations
	printf '{"name":"agentify","version":"4.3.0","commands":[]}\n' \
		>plugins/agentify/.claude-plugin/plugin.json
	printf '{"plugins":[{"name":"agentify","version":"4.3.0"}]}\n' \
		>.claude-plugin/marketplace.json
	# Seed a real migration so bump-version doesn't refuse on missing-doc.
	touch plugins/agentify/migrations/v4.3.0-to-v4.4.0.md
	git add . && git commit -q -m "chore: seed"
	git tag -a v4.3.0 -m "v4.3.0"

	# One feat commit so bump-version computes a minor bump to 4.4.0.
	git commit --allow-empty -q -m "feat(api): add new endpoint"
}

teardown() {
	cd /
	rm -rf "$SANDBOX"
}

# Helper: drop a mocked `mv` on PATH that fails when the target is
# marketplace.json. This simulates the failure mode B-3 specifically
# addresses: first mv (plugin.json) succeeds, second mv (marketplace.json)
# fails mid-transaction. Without rollback, plugin.json is torn — already
# at the new version while marketplace.json is stuck at the old. With
# rollback, plugin.json is restored from .bak.
#
# We inject `mv` rather than `jq` because set -euo pipefail makes a
# second-jq failure abort the script BEFORE either mv runs (so even
# the pre-B-3 code accidentally exhibits atomicity in that path). The
# realistic B-3 hazard is a partial mv sequence.
inject_mv_fault_on_marketplace() {
	local bin="$SANDBOX/.fault-bin"
	mkdir -p "$bin"
	cat >"$bin/mv" <<'EOF'
#!/usr/bin/env bash
# Mock mv: fail when the LAST argument (target) ends with marketplace.json.
# Real /usr/bin/mv for everything else.
target=""
for arg in "$@"; do target="$arg"; done
case "$target" in
    *marketplace.json) echo "mock mv: simulated failure on marketplace.json" >&2; exit 1 ;;
    *) exec /usr/bin/mv "$@" ;;
esac
EOF
	chmod +x "$bin/mv"
	export PATH="$bin:$PATH"
}

@test "bump-version: marketplace.json write failure rolls back plugin.json" {
	plugin_pre=$(sha256sum plugins/agentify/.claude-plugin/plugin.json | cut -d' ' -f1)
	market_pre=$(sha256sum .claude-plugin/marketplace.json | cut -d' ' -f1)

	inject_mv_fault_on_marketplace

	# bump-version should fail (exit non-zero) and restore both manifests.
	AGT_BUMP_REPO_ROOT="$SANDBOX" run bash "$REPO_ROOT/bin/bump-version.sh"
	[ "$status" -ne 0 ]

	plugin_post=$(sha256sum plugins/agentify/.claude-plugin/plugin.json | cut -d' ' -f1)
	market_post=$(sha256sum .claude-plugin/marketplace.json | cut -d' ' -f1)

	[ "$plugin_pre" = "$plugin_post" ] || {
		echo "plugin.json was NOT restored after marketplace failure" >&2
		echo "  pre:  $plugin_pre" >&2
		echo "  post: $plugin_post" >&2
		cat plugins/agentify/.claude-plugin/plugin.json >&2
		false
	}
	[ "$market_pre" = "$market_post" ] || {
		echo "marketplace.json was NOT restored" >&2
		false
	}
}

@test "bump-version: snapshot .bak files are removed on successful transaction" {
	# Without injected fault, both writes succeed; .bak files must be gone.
	AGT_BUMP_REPO_ROOT="$SANDBOX" run bash "$REPO_ROOT/bin/bump-version.sh" --print
	[ "$status" -eq 0 ]

	# A real (non-print) run would also clean up; --print exits before
	# the transaction. Run a real bump to test cleanup explicitly.
	AGT_BUMP_REPO_ROOT="$SANDBOX" run bash "$REPO_ROOT/bin/bump-version.sh"
	[ "$status" -eq 0 ]

	# Assert no .bak.<pid> files remain.
	! ls plugins/agentify/.claude-plugin/plugin.json.bak.* 2>/dev/null
	! ls .claude-plugin/marketplace.json.bak.* 2>/dev/null
}

@test "bump-version: successful transaction leaves both manifests at new version" {
	AGT_BUMP_REPO_ROOT="$SANDBOX" run bash "$REPO_ROOT/bin/bump-version.sh"
	[ "$status" -eq 0 ]
	# Both must now be at 4.4.0.
	plugin_v=$(jq -r .version plugins/agentify/.claude-plugin/plugin.json)
	market_v=$(jq -r '.plugins[0].version' .claude-plugin/marketplace.json)
	[ "$plugin_v" = "4.4.0" ]
	[ "$market_v" = "4.4.0" ]
}
