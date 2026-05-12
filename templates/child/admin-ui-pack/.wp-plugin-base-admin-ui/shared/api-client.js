import apiFetch from "@wordpress/api-fetch";

export function getAdminUiConfig() {
  const slug = "__PLUGIN_SLUG__";
  return window.wpPluginBaseAdminUi?.[slug] || {};
}

export function getRestNamespace() {
  return getAdminUiConfig().restNamespace || "__REST_API_NAMESPACE__";
}

export function getOperationSummary(operationId) {
  return getAdminUiConfig().operations?.[operationId] || null;
}

function buildNamespacedPath(route) {
  const normalized = route.startsWith("/") ? route : `/${route}`;
  return `/${getRestNamespace()}${normalized}`;
}

function normalizePath(path) {
  return path.startsWith("/") ? path : `/${path}`;
}

function isNamespacedPath(path) {
  const normalized = normalizePath(path);
  const namespace = `/${getRestNamespace()}`;

  return (
    normalized === namespace ||
    normalized.startsWith(`${namespace}/`) ||
    normalized.startsWith(`${namespace}?`)
  );
}

export function getOperationPath(operationId) {
  const operation = getOperationSummary(operationId);

  if (!operation?.route) {
    throw new Error(`Unknown admin UI operation: ${operationId}`);
  }

  return buildNamespacedPath(operation.route);
}

export function getPath(path) {
  return isNamespacedPath(path) ? normalizePath(path) : buildNamespacedPath(path);
}

/**
 * @deprecated Use `getOperationPath()` for registered operations or `getPath()` for explicit raw paths.
 */
export function getRestPath(path) {
  return getPath(path);
}

/**
 * Executes a managed REST operation and propagates any `apiFetch` errors.
 *
 * Callers are expected to handle rejections with `try/catch`.
 */
export async function fetchOperation(operationId, options = {}) {
  return apiFetch({
    path: getOperationPath(operationId),
    ...options,
  });
}

export async function fetchPath(path, options = {}) {
  return apiFetch({
    path: getPath(path),
    ...options,
  });
}
