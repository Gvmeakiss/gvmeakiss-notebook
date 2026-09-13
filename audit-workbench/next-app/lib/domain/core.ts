import { CONFIG } from "./config.js";
import { createCore } from "./legacy-core.js";
import type { Core } from "@/types/audit";
export { CONFIG };
export const K = createCore({
  CONFIG,
  crypto: globalThis.crypto,
}) as unknown as Core;
