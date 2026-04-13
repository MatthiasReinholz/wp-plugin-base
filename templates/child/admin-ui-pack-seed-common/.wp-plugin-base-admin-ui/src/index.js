import "./style.scss";
import { createElement, render } from "@wordpress/element";
import App from "./app";
import { getAdminUiConfig } from "../shared/api-client";

const rootId = getAdminUiConfig().rootId;
const target = rootId ? document.getElementById(rootId) : null;

if (target) {
  render(createElement(App), target);
}
