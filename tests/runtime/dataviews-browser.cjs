/** Browser acceptance for the real DataViews starter and installed WordPress packages. */
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const http = require("node:http");
const os = require("node:os");
const path = require("node:path");
const { createRequire } = require("node:module");

async function main() {
  const installDir = path.resolve(process.argv[2]);
  const packageRequire = createRequire(path.join(installDir, "package.json"));
  const webpack = packageRequire("webpack");
  const MiniCssExtractPlugin = packageRequire("mini-css-extract-plugin");
  const { chromium } = packageRequire("@playwright/test");
  const fixture = await fs.mkdtemp(
    path.join(os.tmpdir(), "wp-base-dataviews-browser-"),
  );
  let browser;
  let server;
  try {
    await fs.mkdir(path.join(fixture, "src"));
    await fs.mkdir(path.join(fixture, "shared"));
    const source = path.resolve(
      __dirname,
      "../../templates/child/admin-ui-pack-seed-dataviews/.wp-plugin-base-admin-ui/src/app.js",
    );
    await fs.copyFile(source, path.join(fixture, "src/app.js"));
    await fs.copyFile(
      path.join(path.dirname(source), "dataviews.scss"),
      path.join(fixture, "src/dataviews.scss"),
    );
    await fs.writeFile(
      path.join(fixture, "shared/api-client.js"),
      `
export function getAdminUiConfig() { return { pluginName: 'DataViews acceptance' }; }
export async function fetchOperation(operation) {
  if (operation === 'example-items.list') return { items: Array.from({length:25}, (_, i) => ({id:String(i+1), name:'Record ' + String(i+1).padStart(2,'0'), description:'Example ' + (i+1), status:i%2 ? 'enabled' : 'stable'})) };
  return { message: 'Hello' };
}
`,
    );
    await fs.writeFile(
      path.join(fixture, "src/index.js"),
      `
import { createElement, createRoot } from '@wordpress/element';
import { setLocaleData } from '@wordpress/i18n';
import App from './app';
setLocaleData({ '': { domain: '__PLUGIN_SLUG__', lang:'fr' }, stable:['stable traduit'], enabled:['active traduit'] }, '__PLUGIN_SLUG__');
createRoot(document.getElementById('root')).render(createElement(App));
`,
    );
    await new Promise((resolve, reject) => {
      const compiler = webpack({
        mode: "development",
        entry: path.join(fixture, "src/index.js"),
        output: { path: path.join(fixture, "build"), filename: "app.js" },
        resolve: {
          modules: ["node_modules", path.join(installDir, "node_modules")],
        },
        resolveLoader: { modules: [path.join(installDir, "node_modules")] },
        module: {
          rules: [
            {
              test: /\.s?css$/,
              sideEffects: true,
              use: [MiniCssExtractPlugin.loader, "css-loader", "sass-loader"],
            },
          ],
        },
        plugins: [new MiniCssExtractPlugin({ filename: "style.css" })],
        performance: { hints: false },
      });
      compiler.run((error, stats) =>
        compiler.close(() => {
          if (error || stats.hasErrors())
            reject(
              error || new Error(stats.toString({ all: false, errors: true })),
            );
          else resolve();
        }),
      );
    });
    server = http.createServer(async (request, response) => {
      if (request.url === "/style.css") {
        response.setHeader("Content-Type", "text/css");
        response.end(await fs.readFile(path.join(fixture, "build/style.css")));
      } else if (request.url === "/app.js") {
        response.setHeader("Content-Type", "text/javascript");
        response.end(await fs.readFile(path.join(fixture, "build/app.js")));
      } else {
        response.setHeader("Content-Type", "text/html");
        response.end(
          '<!doctype html><html><head><meta charset="utf-8"><title>DataViews acceptance</title><link rel="stylesheet" href="/style.css"></head><body><div id="root"></div><script src="/app.js"></script></body></html>',
        );
      }
    });
    await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
    browser = await chromium.launch(
      process.env.WP_PLUGIN_BASE_TEST_BROWSER_CHANNEL
        ? { channel: process.env.WP_PLUGIN_BASE_TEST_BROWSER_CHANNEL }
        : {},
    );
    const page = await browser.newPage({
      viewport: { width: 1440, height: 1100 },
    });
    const errors = [];
    page.on("pageerror", (error) => errors.push(error.message));
    await page.goto(`http://127.0.0.1:${server.address().port}`);
    await page
      .getByRole("columnheader", { name: "Name", exact: true })
      .waitFor()
      .catch(async (error) => {
        console.error(errors, await page.locator("body").innerText());
        throw error;
      });
    const rows = page.locator("tbody tr");
    await page.waitForFunction(
      () => document.querySelectorAll("tbody tr").length === 10,
    );
    assert.equal(await rows.count(), 10);
    assert.match(await rows.first().innerText(), /Record 01/);
    const search = page.getByRole("searchbox");
    await search.fill("Record 25");
    await page.waitForFunction(
      () => document.querySelectorAll("tbody tr").length === 1,
    );
    assert.match(await rows.first().innerText(), /Record 25/);
    await search.fill("");
    await page.waitForFunction(
      () => document.querySelectorAll("tbody tr").length === 10,
    );
    await page.getByRole("button", { name: "Next page", exact: true }).click();
    await page.waitForFunction(() =>
      document.querySelector("tbody tr")?.textContent.includes("Record 11"),
    );
    await search.fill("Record 25");
    await page.waitForFunction(
      () => document.querySelectorAll("tbody tr").length === 1,
    );
    assert.match(await rows.first().innerText(), /Record 25/);
    await search.fill("");
    await page.waitForFunction(
      () => document.querySelectorAll("tbody tr").length === 10,
    );
    await page
      .getByRole("columnheader", { name: "Name", exact: true })
      .getByRole("button")
      .click();
    await page
      .getByRole("menuitemradio", { name: "Sort descending", exact: true })
      .click();
    await page.waitForFunction(() =>
      document.querySelector("tbody tr")?.textContent.includes("Record 25"),
    );
    await page.getByRole("button", { name: "Next page", exact: true }).click();
    await page.waitForFunction(() =>
      document.querySelector("tbody tr")?.textContent.includes("Record 15"),
    );
    await page.getByRole("button", { name: "Next page", exact: true }).click();
    await page.waitForFunction(
      () => document.querySelectorAll("tbody tr").length === 5,
    );
    assert.equal(
      await page
        .getByRole("button", { name: "Next page", exact: true })
        .isDisabled(),
      true,
    );
    await page.getByRole("button", { name: "Add filter", exact: true }).click();
    await page.getByRole("menuitem", { name: "Status", exact: true }).click();
    await page.getByText("stable traduit", { exact: true }).last().click();
    await page.keyboard.press("Escape");
    await page.waitForFunction(
      () =>
        document.querySelectorAll("tbody tr").length === 10 &&
        [...document.querySelectorAll("tbody tr")].every((row) =>
          row.textContent.includes("stable traduit"),
        ),
    );
    assert.match(await rows.first().innerText(), /Record 25/);
    await page.getByRole("button", { name: "Next page", exact: true }).click();
    await page.waitForFunction(
      () => document.querySelectorAll("tbody tr").length === 3,
    );
    assert.match(await rows.first().innerText(), /Record 05/);
    assert.equal(
      await page
        .getByRole("button", { name: "Next page", exact: true })
        .isDisabled(),
      true,
    );
    assert.equal(
      await page.getByText("Status: stable traduit", { exact: true }).count(),
      1,
    );
    assert.deepEqual(errors, []);
    console.log("DataViews browser acceptance passed.");
  } finally {
    if (browser) await browser.close();
    if (server) await new Promise((resolve) => server.close(resolve));
    await fs.rm(fixture, { recursive: true, force: true });
  }
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
