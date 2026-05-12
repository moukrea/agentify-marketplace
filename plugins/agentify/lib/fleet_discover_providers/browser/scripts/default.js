/**
 * default.js — reference fleet-discovery browser script. Returns an
 * empty list; replace with a portal-specific implementation.
 *
 * Example (Puppeteer-based scrape of an internal wiki):
 *
 *   const puppeteer = require("puppeteer");
 *   async function discover(ctx) {
 *     const browser = await puppeteer.launch({ headless: true });
 *     const page = await browser.newPage();
 *     await page.goto(ctx.targetUrl);
 *     const urls = await page.$$eval(
 *       "a[href^='https://github.com/']",
 *       (as) => as.map((a) => a.href),
 *     );
 *     await browser.close();
 *     return urls.map((url) => {
 *       const m = url.match(/github\.com\/([^/]+)\/([^/?#]+)/);
 *       return { url, owner: m && m[1], name: m && m[2] };
 *     });
 *   }
 */

async function discover(_ctx) {
	process.stderr.write(
		"fleet-discover-browser-default: stub script returns []; supply a portal-specific script.\n",
	);
	return [];
}

module.exports = { discover };
