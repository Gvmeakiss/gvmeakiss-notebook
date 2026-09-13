import type { NextConfig } from "next";
import { APP_BASE_URL } from "./lib/service/static-config";
const config: NextConfig = {
  output: "export", basePath: APP_BASE_URL, trailingSlash: true,
  images: {unoptimized:true},
};
export default config;
