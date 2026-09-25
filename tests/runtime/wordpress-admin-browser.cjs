/** Verify the production bundle against WordPress' real script registry and REST API. */
const assert = require("node:assert/strict");
const path = require("node:path");
const { createRequire } = require("node:module");

async function main() {
  const installDir = path.resolve(process.argv[2]);
  const origin = process.argv[3];
  const variant = process.argv[4] || "dataviews";
  assert.ok(
    ["basic", "dataviews"].includes(variant),
    "Expected a starter variant",
  );
  const packageRequire = createRequire(path.join(installDir, "package.json"));
  const { chromium } = packageRequire("@playwright/test");
  const browser = await chromium.launch(
    process.env.WP_PLUGIN_BASE_TEST_BROWSER_CHANNEL
      ? { channel: process.env.WP_PLUGIN_BASE_TEST_BROWSER_CHANNEL }
      : {},
  );
  try {
    const page = await browser.newPage({
      viewport: { width: 1440, height: 1100 },
    });
    const errors = [];
    page.on("pageerror", (error) => errors.push(error.message));
    await page.goto(`${origin}/wp-login.php`);
    await page.locator("#user_login").fill("admin");
    await page.locator("#user_pass").fill("password");
    await Promise.all([
      page.waitForURL(/wp-admin/),
      page.locator("#wp-submit").click(),
    ]);
    await page.goto(
      `${origin}/wp-admin/admin.php?page=runtime-pack-ready-admin-ui`,
    );
    if (variant === "dataviews") {
      const rows = page.locator("#runtime-pack-ready-admin-ui-root tbody tr");
      await rows
        .first()
        .waitFor()
        .catch(async (error) => {
          console.error(errors, await page.locator("body").innerText());
          throw error;
        });
      assert.equal(await rows.count(), 3);
      assert.equal(
        await page
          .locator('link[id="runtime-pack-ready-admin-ui-components-css"]')
          .count(),
        1,
      );
      assert.equal(
        await page
          .locator('link[id="runtime-pack-ready-admin-ui-components-css"]')
          .evaluate((link) => Boolean(link.sheet?.cssRules.length)),
        true,
        "Bundled component stylesheet must load usable CSS rules",
      );

      await page.getByRole("searchbox").fill("Settings");
      await page.waitForFunction(
        () =>
          document.querySelectorAll(
            "#runtime-pack-ready-admin-ui-root tbody tr",
          ).length === 1,
      );
      assert.match(await rows.first().innerText(), /Settings/);
    } else {
      const app = page.locator("#runtime-pack-ready-admin-ui-root");
      const overview = app.getByRole("button", {
        name: "Overview",
        exact: true,
        pressed: true,
      });
      await overview.waitFor();
      assert.equal(await overview.getAttribute("aria-pressed"), "true");
      const settings = app.getByRole("button", {
        name: "Settings",
        exact: true,
      });
      await settings.click();
      assert.equal(
        await app
          .getByRole("button", { name: "Settings", exact: true, pressed: true })
          .getAttribute("aria-pressed"),
        "true",
      );
    }
    const message = page.getByRole("textbox", { name: "Message", exact: true });
    await message.fill("Browser contract saved value");
    await page.getByRole("button", { name: "Save", exact: true }).click();
    await page
      .getByText("Browser contract saved value", { exact: true })
      .waitFor();
    await page.reload();
    await page.waitForFunction(() =>
      [...document.querySelectorAll("input")].some(
        (input) => input.value === "Browser contract saved value",
      ),
    );
    assert.deepEqual(errors, []);
    console.log(
      "Built admin UI renders, queries and saves through real WordPress.",
    );
  } finally {
    await browser.close();
  }
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
