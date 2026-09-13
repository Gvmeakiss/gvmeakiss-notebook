import type { Status } from "@/types/audit";
export interface FieldConfig {
  key: string;
  label: string;
  type: "text" | "textarea" | "date" | "boolean" | "number" | "json";
  hidden?: boolean;
  aliases?: string[];
  required?: boolean;
  requiredWhenOpen?: boolean;
  maxLength?: number;
  importOptional?: boolean;
  legacy?: boolean;
  min?: number;
  max?: number;
  step?: number;
  modules?: string[];
}
export interface AuditConfig {
  appName: string;
  storageKey: string;
  schemaVersion: number;
  theme: { brand: string; brandSoft: string; brandText: string };
  ui: { defaultView: string };
  modules: { id: string; label: string; aliases?: string[] }[];
  legacyModules: { id: string; label: string; aliases?: string[] }[];
  fields: FieldConfig[];
  statuses: Record<
    Status,
    { label: string; color: string; background: string }
  >;
  board: {
    textFields: string[];
    showEmptyModules: boolean;
    defaultSort: string;
  };
  limits: { maxFileBytes: number; maxRecords: number; maxSnapshots: number };
  excel: {
    sheetName: string;
    idLabel: string;
    moduleLabel: string;
    updatedLabel: string;
    statusLabel: string;
  };
}
export const CONFIG: AuditConfig;
