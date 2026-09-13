// Optional hosting prefix, e.g. /audit-workbench. Empty means origin root.
const prefix = process.env.NEXT_PUBLIC_BASE_PATH || "";
if (prefix && (!prefix.startsWith("/") || prefix.startsWith("//") || /[?#]/.test(prefix) || prefix.split("/").includes(".."))) {
  throw new Error("NEXT_PUBLIC_BASE_PATH must be an absolute URL path");
}
export const APP_BASE_URL = prefix.replace(/\/+$/, "");
