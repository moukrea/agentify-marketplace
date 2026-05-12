#!/usr/bin/env node
/**
 * runner.js — browser task-backend driver dispatcher.
 *
 * Reads a JSON array of arguments from stdin, dispatches to the
 * user-supplied per-target script's exported function matching
 * process.env.AGENTIFY_VERB, and prints the function's return value
 * (auto-JSON-stringified for objects/arrays) to stdout.
 *
 * Environment:
 *   AGENTIFY_VERB    — verb name (e.g. "taskCreate")
 *   AGENTIFY_SCRIPT  — script filename under /scripts/ (default "default.js")
 *   TARGET_URL       — passed through to the user script for convenience
 *
 * The runner is shipped by the plugin; the user script lives under
 * plugins/agentify/lib/task_backend_drivers/browser/scripts/ and is
 * authored per target. The "puppeteer" / "playwright" choice is the
 * user's; the runner does not require either dependency.
 */

const fs = require("fs");
const path = require("path");

async function main() {
	const verb = process.env.AGENTIFY_VERB;
	const scriptName = process.env.AGENTIFY_SCRIPT || "default.js";
	const scriptPath = path.join("/scripts", scriptName);
	if (!verb) {
		process.stderr.write("runner: AGENTIFY_VERB env not set\n");
		process.exit(64);
	}
	if (!fs.existsSync(scriptPath)) {
		process.stderr.write(
			`runner: script ${scriptPath} not found. Place it under ` +
				`plugins/agentify/lib/task_backend_drivers/browser/scripts/ ` +
				`or set AGENTIFY_BROWSER_SCRIPT to point elsewhere.\n`,
		);
		process.exit(64);
	}

	const stdin = await new Promise((resolve) => {
		const chunks = [];
		process.stdin.on("data", (c) => chunks.push(c));
		process.stdin.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
	});
	const args = stdin.trim() ? JSON.parse(stdin) : [];

	const mod = require(scriptPath);
	if (typeof mod[verb] !== "function") {
		process.stderr.write(`runner: ${scriptName} does not export ${verb}\n`);
		process.exit(64);
	}

	try {
		const result = await mod[verb](
			{ targetUrl: process.env.TARGET_URL || "" },
			...args,
		);
		if (result === undefined) return;
		if (typeof result === "string") {
			process.stdout.write(result);
			if (!result.endsWith("\n")) process.stdout.write("\n");
		} else {
			process.stdout.write(JSON.stringify(result));
			process.stdout.write("\n");
		}
	} catch (err) {
		process.stderr.write(`runner: ${verb} threw: ${err && err.stack || err}\n`);
		process.exit(1);
	}
}

main();
