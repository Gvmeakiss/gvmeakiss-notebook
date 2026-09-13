import type { Core, ExcelAdapter, SheetJSLibrary } from "@/types/audit";
export function createExcel(root: {
  CONFIG: unknown;
  KanbanCore: Core;
  XLSX: SheetJSLibrary;
}): ExcelAdapter;
