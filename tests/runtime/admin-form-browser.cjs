/** Browser contracts for safe submissions and recovery in both admin starters. */
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const http = require("node:http");
const os = require("node:os");
const path = require("node:path");
const { createRequire } = require("node:module");

async function main() {
  const installDir = path.resolve(process.argv[2]);
  const variant = process.argv[3];
  assert.ok(
    ["basic", "dataviews"].includes(variant),
    "Expected a starter variant",
  );
  const packageRequire = createRequire(path.join(installDir, "package.json"));
  const webpack = packageRequire("webpack");
  const MiniCssExtractPlugin = packageRequire("mini-css-extract-plugin");
  const { chromium } = packageRequire("@playwright/test");
  const fixture = await fs.mkdtemp(
    path.join(os.tmpdir(), "wp-base-admin-form-"),
  );
  let browser;
  let server;
  try {
    await fs.mkdir(path.join(fixture, "src"));
    await fs.mkdir(path.join(fixture, "shared"));
    const templates = path.resolve(__dirname, "../../templates/child");
    const source = path.join(
      templates,
      `admin-ui-pack-seed-${variant}/.wp-plugin-base-admin-ui/src`,
    );
    await fs.copyFile(
      path.join(source, "app.js"),
      path.join(fixture, "src/app.js"),
    );
    if (variant === "dataviews") {
      await fs.copyFile(
        path.join(source, "dataviews.scss"),
        path.join(fixture, "src/dataviews.scss"),
      );
    }
    await fs.copyFile(
      path.join(
        templates,
        "admin-ui-pack-seed-common/.wp-plugin-base-admin-ui/src/error-boundary.js",
      ),
      path.join(fixture, "src/error-boundary.js"),
    );
    await fs.writeFile(
      path.join(fixture, "shared/api-client.js"),
      `
window.adminRequests = [];
export function getAdminUiConfig() { return { pluginName: 'Admin acceptance' }; }
export async function fetchOperation(operation, options = {}) {
  if (operation === 'settings.update') {
    return new Promise((resolve, reject) => window.adminRequests.push({ data: options.data, resolve, reject }));
  }
  if (location.search === '?load-error') throw null;
  if (operation === 'example-items.list') return { items: [
    { id: 'first', name: 'First record', description: 'Example one', status: 'stable' },
    { id: 'second', name: 'Second record', description: 'Example two', status: 'enabled' }
  ] };
  return { message: 'Original value' };
}
`,
    );
    await fs.writeFile(
      path.join(fixture, "src/index.js"),
      `
import { createElement, createRoot } from '@wordpress/element';
import { setLocaleData } from '@wordpress/i18n';
import App from './app';
import ErrorBoundary from './error-boundary';
setLocaleData({ '': { domain: '__PLUGIN_SLUG__', lang: 'fr' }, 'The admin UI could not finish rendering.': ['Affichage indisponible.'], 'Reload page': ['Recharger la page'] }, '__PLUGIN_SLUG__');
function BrokenApp() { throw new Error('Rendering failed'); }
createRoot(document.getElementById('root')).render(createElement(ErrorBoundary, null, createElement(location.search === '?render-error' ? BrokenApp : App)));
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
      if (request.url === "/app.js") {
        response.setHeader("Content-Type", "text/javascript");
        response.end(await fs.readFile(path.join(fixture, "build/app.js")));
      } else {
        response.setHeader("Content-Type", "text/html");
        response.end(
          '<!doctype html><html><head><meta charset="utf-8"><title>Admin form acceptance</title></head><body><div id="root"></div><script src="/app.js"></script></body></html>',
        );
      }
    });
    await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
    browser = await chromium.launch(
      process.env.WP_PLUGIN_BASE_TEST_BROWSER_CHANNEL
        ? { channel: process.env.WP_PLUGIN_BASE_TEST_BROWSER_CHANNEL }
        : {},
    );
    const page = await browser.newPage();
    const errors = [];
    page.on("pageerror", (error) => errors.push(error.message));
    const url = `http://127.0.0.1:${server.address().port}`;
    await page.goto(url);
    const app = page.locator("#root");
    const message = page.getByRole("textbox", { name: "Message", exact: true });
    await message.waitFor();
    assert.equal(await message.inputValue(), "Original value");
    const save = page.getByRole("button", { name: "Save", exact: true });
    assert.equal(await save.isDisabled(), false);
    if (variant === "basic") {
      assert.equal(
        await page
          .getByRole("button", {
            name: "First record",
            exact: true,
            pressed: true,
          })
          .getAttribute("aria-pressed"),
        "true",
      );
      await page
        .getByRole("button", { name: "Second record", exact: true })
        .click();
      assert.equal(
        await page
          .getByRole("button", {
            name: "Second record",
            exact: true,
            pressed: true,
          })
          .getAttribute("aria-pressed"),
        "true",
      );
    }
    await message.fill("Draft value");
    await page.locator("form").evaluate((form) => {
      form.dispatchEvent(
        new Event("submit", { bubbles: true, cancelable: true }),
      );
      form.dispatchEvent(
        new Event("submit", { bubbles: true, cancelable: true }),
      );
    });
    assert.equal(await page.evaluate(() => window.adminRequests.length), 1);
    assert.equal(await save.isDisabled(), true);
    await message.fill("Preserved edit");
    await page.evaluate(() =>
      window.adminRequests[0].reject(new Error("Request failed")),
    );
    await app.getByText("Request failed", { exact: true }).waitFor();
    assert.equal(await message.inputValue(), "Preserved edit");
    assert.equal(
      await app.getByText("Original value", { exact: true }).count(),
      1,
    );
    assert.equal(await save.isDisabled(), false);
    await save.click();
    assert.equal(await page.evaluate(() => window.adminRequests.length), 2);
    assert.equal(
      await page.evaluate(() => window.adminRequests[1].data.message),
      "Preserved edit",
    );
    await page.evaluate(() =>
      window.adminRequests[1].resolve({ message: "Preserved edit" }),
    );
    await app.getByText("Preserved edit", { exact: true }).waitFor();
    assert.equal(await save.isDisabled(), false);
    await page.goto(`${url}?load-error`);
    await app.getByText("Failed to load settings.", { exact: true }).waitFor();
    assert.equal(await save.isDisabled(), true);
    await page
      .locator("form")
      .evaluate((form) =>
        form.dispatchEvent(
          new Event("submit", { bubbles: true, cancelable: true }),
        ),
      );
    assert.equal(await page.evaluate(() => window.adminRequests.length), 0);
    assert.deepEqual(errors, []);
    await page.goto(`${url}?render-error`);
    await app.getByText("Affichage indisponible.", { exact: true }).waitFor();
    await page
      .getByRole("button", { name: "Recharger la page", exact: true })
      .waitFor();
    console.log(`${variant} admin form browser contracts passed.`);
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
