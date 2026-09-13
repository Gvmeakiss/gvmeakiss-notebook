import { APP_BASE_URL } from "@/lib/service/static-config";
export function $static(path:string):string {
  if (!path || path.split("/").includes("..") || /^[a-z]+:/i.test(path) || path.startsWith("//")) throw new Error("静态资源路径无效");
  return `${APP_BASE_URL}/${path.replace(/^\/+/, "")}`;
}
