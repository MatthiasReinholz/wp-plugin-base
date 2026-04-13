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

export function getRestPath(operationIdOrPath) {
  const operation = getOperationSummary(operationIdOrPath);
  const route = operation?.route || operationIdOrPath;
  const normalized = route.startsWith("/") ? route : `/${route}`;
  return `/${getRestNamespace()}${normalized}`;
}

export async function fetchOperation(operationIdOrPath, options = {}) {
  return apiFetch({
    path: getRestPath(operationIdOrPath),
    ...options,
  });
}
