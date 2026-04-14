import "./style.scss";
import { createElement, createRoot } from "@wordpress/element";
import App from "./app";
import { getAdminUiConfig } from "../shared/api-client";

const rootId = getAdminUiConfig().rootId;
const target = rootId ? document.getElementById(rootId) : null;

if (target) {
  createRoot(target).render(createElement(App));
}
