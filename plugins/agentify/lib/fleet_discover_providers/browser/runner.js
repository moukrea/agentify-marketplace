#!/usr/bin/env node
/**
 * runner.js — fleet-discovery browser provider runner. Loads the
 * user-supplied script and calls its exported `discover` function,
 * then prints a JSON array of peer objects to stdout.
 *
 * Environment:
 *   AGENTIFY_SCRIPT — script filename under /scripts/ (default "default.js")
 *   TARGET_URL      — the portal URL to scrape
 */

const fs = require("fs");
const path = require("path");

async function main() {
	const scriptName = process.env.AGENTIFY_SCRIPT || "default.js";
	const scriptPath = path.join("/scripts", scriptName);
	if (!fs.existsSync(scriptPath)) {
		process.stderr.write(
			`fleet-discover-browser: script ${scriptPath} not found.\n`,
		);
		process.stdout.write("[]\n");
		process.exit(0);
	}
	const mod = require(scriptPath);
	if (typeof mod.discover !== "function") {
		process.stderr.write(
			`fleet-discover-browser: ${scriptName} does not export discover()\n`,
		);
		process.stdout.write("[]\n");
		process.exit(0);
	}
	try {
		const peers = await mod.discover({
			targetUrl: process.env.TARGET_URL || "",
		});
		const now = new Date().toISOString();
		const normalised = (Array.isArray(peers) ? peers : []).map((p) => ({
			url: p.url || "",
			owner: p.owner || "",
			name: p.name || "",
			description: p.description || null,
			source_provider: "browser",
			first_seen_at: p.first_seen_at || now,
		}));
		process.stdout.write(JSON.stringify(normalised) + "\n");
	} catch (err) {
		process.stderr.write(
			`fleet-discover-browser: discover() threw: ${err && err.stack || err}\n`,
		);
		process.stdout.write("[]\n");
	}
}

main();
