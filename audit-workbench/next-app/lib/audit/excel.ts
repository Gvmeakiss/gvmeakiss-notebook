import { $static } from "@/util/public";
import { CONFIG, K } from "@/lib/domain/core";
import { createExcel } from "@/lib/domain/legacy-excel.js";
import type {
  ExcelAdapter,
  SheetJSLibrary,
  AuditRecord,
} from "@/types/audit";
declare global {
  interface Window {
    XLSX?: SheetJSLibrary;
  }
}
let pending: Promise<SheetJSLibrary> | undefined;
export function loadExcel(): Promise<SheetJSLibrary> {
  if (window.XLSX) return Promise.resolve(window.XLSX);
  if (!pending)
    pending = new Promise<SheetJSLibrary>((resolve, reject) => {
      const script = document.createElement("script");
      script.src = $static("/vendor/xlsx.full.min.js");
      script.onload = () =>
        window.XLSX
          ? resolve(window.XLSX)
          : reject(new Error("Excel 组件无效"));
      script.onerror = () => {
        script.remove();
        reject(new Error("Excel 组件未加载，请检查静态资源映射"));
      };
      document.head.append(script);
    }).catch((e) => {
      pending = undefined;
      throw e;
    });
  return pending;
}
export async function excelAdapter(): Promise<ExcelAdapter> {
  return createExcel({
    CONFIG,
    KanbanCore: K,
    XLSX: await loadExcel(),
  }) as unknown as ExcelAdapter;
}
export function download(
  data: BlobPart,
  name: string,
  type = "application/json",
) {
  const url = URL.createObjectURL(new Blob([data], { type }));
  const a = document.createElement("a");
  a.href = url;
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 30000);
}
export async function exportExcel(
  records: AuditRecord[],
  name = "稽核工作台账",
  frozen = false,
  legacy = false,
  teamId?: string,
) {
  const X = await loadExcel(),
    E = await excelAdapter();
  download(
    X.write(E.workbook(records.map(r => ({...r, ...(teamId ? {teamId} : {})})), { frozen, legacy, teamId }), {
      type: "array",
      bookType: "xlsx",
      compression: true,
    }),
    `${name}_${K.localDate()}_${Date.now()}.xlsx`,
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  );
}
