import type { Core } from "@/types/audit";
export function createCore(root: { CONFIG: unknown; crypto?: Crypto }): Core;
