#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
API_CLIENT_PATH="$ROOT_DIR/templates/child/admin-ui-pack/.wp-plugin-base-admin-ui/shared/api-client.js"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}

trap cleanup EXIT

cp "$API_CLIENT_PATH" "$TMP_DIR/api-client.mjs"
sed 's#^import apiFetch from "@wordpress/api-fetch";#import apiFetch from "./api-fetch-stub.mjs";#' "$TMP_DIR/api-client.mjs" > "$TMP_DIR/api-client.mjs.tmp"
mv "$TMP_DIR/api-client.mjs.tmp" "$TMP_DIR/api-client.mjs"

cat > "$TMP_DIR/api-fetch-stub.mjs" <<'EOF_STUB'
const calls = [];

export function getCalls() {
  return calls;
}

export default async function apiFetch(args) {
  calls.push(args);
  return { ok: true, path: args.path };
}
EOF_STUB

TMP_DIR="$TMP_DIR" node --input-type=module <<'NODE'
import { pathToFileURL } from "node:url";

const tmpDir = process.env.TMP_DIR;
const clientModule = await import(pathToFileURL(`${tmpDir}/api-client.mjs`).href);
const stubModule = await import(pathToFileURL(`${tmpDir}/api-fetch-stub.mjs`).href);

globalThis.window = {
  wpPluginBaseAdminUi: {
    "__PLUGIN_SLUG__": {
      restNamespace: "example-plugin/v1",
      operations: {
        "settings.read": { route: "/settings" },
      },
    },
  },
};

if (clientModule.getRestNamespace() !== "example-plugin/v1") {
  throw new Error("Expected the admin UI client to prefer the injected runtime namespace.");
}

if (clientModule.getOperationPath("settings.read") !== "/example-plugin/v1/settings") {
  throw new Error("Expected operation ids to resolve through the managed operation registry.");
}

if (clientModule.getPath("health") !== "/example-plugin/v1/health") {
  throw new Error("Expected raw paths to be normalized into the managed namespace.");
}

if (clientModule.getRestPath("/health") !== "/example-plugin/v1/health") {
  throw new Error("Expected getRestPath() to remain a raw-path compatibility alias.");
}

let unknownOperationThrew = false;
try {
  clientModule.getOperationPath("settings.missing");
} catch (error) {
  unknownOperationThrew = error instanceof Error && error.message.includes("Unknown admin UI operation");
}

if (!unknownOperationThrew) {
  throw new Error("Expected unknown operation ids to fail loudly.");
}

await clientModule.fetchOperation("settings.read", { method: "GET" });
await clientModule.fetchPath("/health", { method: "POST" });

const calls = stubModule.getCalls();

if (calls.length !== 2) {
  throw new Error("Expected both fetchOperation() and fetchPath() to delegate to apiFetch.");
}

if (calls[0].path !== "/example-plugin/v1/settings" || calls[0].method !== "GET") {
  throw new Error("Expected fetchOperation() to use the registry-backed route.");
}

if (calls[1].path !== "/example-plugin/v1/health" || calls[1].method !== "POST") {
  throw new Error("Expected fetchPath() to use the explicit raw path.");
}

console.log("Admin UI API client tests passed.");
NODE
