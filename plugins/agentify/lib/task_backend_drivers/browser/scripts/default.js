/**
 * default.js — reference no-op browser task-backend script.
 *
 * Replace this with a target-specific script implementing each verb
 * the agentify task-backend interface calls. The runner injects:
 *
 *   - process.env.TARGET_URL (configurable via
 *     agentify.config.json:.task_backend.endpoint)
 *   - process.env.AGENTIFY_VERB
 *
 * and stdin carries a JSON array of arguments. Return a string or
 * object; the runner JSON-encodes objects.
 *
 * For browser automation, install puppeteer or playwright into the
 * container image specified by agentify.config.json:.task_backend.browser.image
 * (default node:lts-bookworm). Example:
 *
 *   const puppeteer = require("puppeteer");
 *   async function prdCreate(ctx, title, bodyFile) {
 *     const browser = await puppeteer.launch({ headless: true });
 *     const page = await browser.newPage();
 *     await page.goto(ctx.targetUrl + "/prd/new");
 *     // ... fill form, submit, scrape ref...
 *     await browser.close();
 *     return "legacy://prd/" + newId;
 *   }
 *
 * The stubs below print one-line markers so the bash dispatcher's
 * tests can observe that dispatch happened end-to-end.
 */

const noop = (verb) => async () => {
	process.stderr.write(`browser-default: ${verb} is a stub; provide a target-specific script.\n`);
	return `browser://stub/${verb}/${Date.now()}`;
};

module.exports = {
	charterCreate:    noop("charterCreate"),
	charterGet:       noop("charterGet"),
	prdCreate:        noop("prdCreate"),
	prdGet:           noop("prdGet"),
	brainstormCreate: noop("brainstormCreate"),
	planCreate:       noop("planCreate"),
	planGet:          noop("planGet"),
	taskCreate:       noop("taskCreate"),
	taskList:         noop("taskList"),
	taskGet:          noop("taskGet"),
	taskUpdate:       noop("taskUpdate"),
	taskLink:         noop("taskLink"),
	taskSearch:       noop("taskSearch"),
	adrCreate:        noop("adrCreate"),
	validate:         noop("validate"),
};
