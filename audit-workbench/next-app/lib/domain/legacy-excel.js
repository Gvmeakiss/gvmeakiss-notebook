import { CONFIG as V1_CONFIG } from "./v1-config.js";
import { createCore as createV1Core } from "./v1-core.js";
/* Excel 边界适配：只有此文件依赖本地 SheetJS。其他业务逻辑不依赖 Excel 库。 */
export function createExcel(root) {
  "use strict";
  const C = root.CONFIG,
    K = root.KanbanCore;
  function columns() {
    return [
      { key: "id", label: C.excel.idLabel },
      { key: "module", label: C.excel.moduleLabel },
      ...C.fields.filter(f => f.type !== "json"),
      { key: "updatedAt", label: C.excel.updatedLabel },
    ];
  }
  function workbook(records, options = {}) {
    if (options.legacy)
      return createExcel({
        CONFIG: V1_CONFIG,
        KanbanCore: createV1Core({ CONFIG: V1_CONFIG }),
        XLSX: root.XLSX,
      }).workbook(records, { frozen: options.frozen, teamId: options.teamId });
    const X = root.XLSX;
    if (!X) throw new Error("Excel 库未加载，请检查 vendor 文件夹是否完整");
    const cols = columns().filter(
      (c) => !c.legacy || records.some((r) => r[c.key]),
    );
    const rows = [cols.map((c) => c.label).concat(C.excel.statusLabel)];
    for (const r of records) {
      rows.push(
        cols
          .map((c) => {
            if (c.key === "module") return K.moduleName(r.module);
            if (c.type === "boolean") return r[c.key] ? "是" : "否";
            if (c.key === "progressPercent") return K.percent(r) ?? "";
            if (c.type === "date" && r[c.key]) {
              // 日期使用数值序列与显示格式；用户文字始终由 aoa_to_sheet 写成字符串单元格。
              const serial =
                (Date.UTC(
                  ...r[c.key].split("-").map((n, i) => +n - (i === 1 ? 1 : 0)),
                ) -
                  Date.UTC(1899, 11, 30)) /
                86400000;
              return {
                t: "n",
                v: serial < 61 ? serial - 1 : serial,
                z: "yyyy-mm-dd",
              };
            }
            return String(r[c.key] ?? "");
          })
          .concat(
            C.statuses[options.frozen ? r.frozenStatus : K.status(r)].label,
          ),
      );
    }
    const ws = X.utils.aoa_to_sheet(rows);
    // 工作编号可见，便于关联分批明细；更新时间和团队身份默认隐藏。
    ws["!cols"] = cols
      .map((c) => ({
        wch:
          c.type === "textarea"
            ? 45
            : c.key === "id" || c.key === "updatedAt"
              ? 38
              : 22,
        hidden: c.key === "updatedAt" || c.hidden,
      }))
      .concat({ wch: 20 });
    ws["!autofilter"] = {
      ref: X.utils.encode_range(
        { r: 0, c: 0 },
        { r: Math.max(0, rows.length - 1), c: cols.length },
      ),
    };
    const wb = X.utils.book_new();
    X.utils.book_append_sheet(wb, ws, C.excel.sheetName);
    const instructions = [
      ["填写说明", "要求"],
      ["本次升级", "旧数据先导出新版Excel，补充字段后导入；已有编号保留。未填写新增字段保持未知，不自动推测。"],
      ["团队", "导出文件绑定当前团队。旧文件无团队时，导入需确认归属；不能将其他团队文件混入。"],
      ["挽损金额", "主表金额单位为元、最多两位小数。应挽损与实际分别填写；实际大于0须有成果编号、确认依据、确认日期和实现方式。"],
      ["挽损明细", "分批回款填挽损明细表：主表工作编号、实际日期、正金额、实现方式、确认依据。新增明细编号留空；已有编号保留。明细合计自动替代主表累计实际金额。"],
      ["统计口径", "实现方式：资金追回、核减支付、其他已确认实现；期间统计只计算有日期的明细，累计值不重复相加。"],
      ["关注级别", "普通、重点、紧急。当前阻碍、需要协调可填写具体事项。"],
      ["成果状态", "待确认、已确认、研究中、形成方案、被采纳、已应用、推进中、已落实、待回复、已回复。已确认须有依据和日期。"],
      ["关联工作", "关联工作编号填写其他来源工作编号，多项以英文逗号分隔；同一挽损成果只登记一次。"],
      ["阶段历史", "历史与明细表保留已留存的阶段JSON，不要改写。正常修改主表阶段字段再导入时，系统会保留修改前内容。"],
      ["唯一编号", "新工作可留空；更新已有工作时请保留编号，不要重新生成。"],
      ["模块", C.modules.map((m) => m.label).join("、")],
      ["项目整体交付日期", "填写 Excel 日期或 YYYY-MM-DD，例如 2026-09-30。"],
      [
        "项目进度（%）",
        "填写 0–100 整数，如 60（不是 0.6）。空白表示未填写，整项已完成时填 100。",
      ],
      ["是否完成", "填写 是／否；空白按否处理。完成指整项工作完成。"],
      [
        "负责人／参与人员",
        "多人用顿号分隔，例如演示甲、演示乙；一项工作只保留一个编号。",
      ],
      [
        "阶段内容",
        "上一阶段填已完成内容和实际日期，本阶段填任务、目前描述和预期日期，下一阶段填工作内容。没有上一/下一阶段时可留空。",
      ],
      [
        "本阶段预期完成时间",
        "仅用于阶段超期提醒；整项红绿状态仍根据项目整体交付日期计算。",
      ],
      [
        "旧数据",
        "兼容旧表头；旧三促／三函／挽损导入后在待归类区由汇总人分配，不复制记录。",
      ],
      ["更新时间", "已有记录保留原值；新工作可留空，导入时生成。"],
      ["实际状态（只读）", "根据完成标记与日期计算，导入不读取此列。"],
      ["合并", "同编号不同内容需要汇总人逐条选择，不按更新时间自动覆盖。"],
      [
        "注意",
        `主表可填写；“历史与明细”和“团队信息”为系统保留数据，请勿删除或修改。禁止数据区公式。`,
      ],
    ];
    const help = X.utils.aoa_to_sheet(instructions);
    help["!cols"] = [{ wch: 24 }, { wch: 95 }];
    X.utils.book_append_sheet(wb, help, "填写说明");
    const detailRows = [["工作编号", "内容类型", "内容JSON"]];
    for (const r of records) for (const kind of ["stageHistory"]) for (const entry of r[kind] || []) {
      const json = JSON.stringify(entry);
      if (json.length > 32000) throw new Error("单条历史过长，无法完整导出Excel，请使用JSON备份");
      detailRows.push([r.id, kind, json]);
    }
    if (detailRows.length > 100001) throw new Error("历史明细超过Excel导出上限，请使用JSON备份");
    X.utils.book_append_sheet(wb, X.utils.aoa_to_sheet(detailRows), "历史与明细");
    const recoveryRows = [["工作编号", "实现日期", "金额（元）", "实现方式", "确认依据", "备注", "明细编号（保留）"]];
    for (const r of records) for (const e of r.recoveryEntries || []) recoveryRows.push([r.id,e.date,e.amount,e.method,e.evidence,e.note || '',e.id]);
    const recoverySheet = X.utils.aoa_to_sheet(recoveryRows);
    recoverySheet["!cols"] = [{wch:38},{wch:16},{wch:18},{wch:20},{wch:45},{wch:35},{wch:38}];
    X.utils.book_append_sheet(wb,recoverySheet,"挽损明细");
    if (options.teamId) X.utils.book_append_sheet(wb, X.utils.aoa_to_sheet([["所属团队编号",options.teamId]]), "团队信息");
    return wb;
  }
  function read(buffer, options = {}) {
    const X = root.XLSX;
    if (!X) throw new Error("Excel 库未加载");
    const bytes = new Uint8Array(buffer);
    if (bytes[0] !== 0x50 || bytes[1] !== 0x4b)
      throw new Error("不是有效的 .xlsx 文件，请勿仅修改扩展名");
    const wb = X.read(buffer, {
      type: "array",
      cellDates: false,
      cellFormula: true,
      cellNF: true,
      sheetRows: 100003,
    });
    const meta = wb.Sheets["团队信息"];
    const fileTeam = meta?.B1?.v;
    if (meta?.B1?.f || (fileTeam !== undefined && typeof fileTeam !== "string")) throw new Error("团队信息格式无效");
    if (fileTeam && options.teamId && fileTeam !== options.teamId) throw new Error("文件属于其他团队，请切换所属团队");
    const details = new Map();
    const detailSheet = wb.Sheets["历史与明细"];
    if (detailSheet?.["!ref"]) {
      const area = X.utils.decode_range(detailSheet["!fullref"] || detailSheet["!ref"]);
      if (area.e.r > 100000 || area.e.c > 2) throw new Error("历史明细范围过大");
      if (detailSheet.A1?.v !== "工作编号" || detailSheet.B1?.v !== "内容类型" || detailSheet.C1?.v !== "内容JSON") throw new Error("历史明细表头无效");
      for (let i=1; i<=area.e.r; i++) {
        const cells = [0,1,2].map(c => detailSheet[X.utils.encode_cell({r:i,c})]);
        if (cells.every(c => !c || c.v === "")) continue;
        if (cells.some(c => c?.f)) throw new Error("历史明细不能含公式");
        const [id,kind,json] = cells.map(c => c?.v);
        if (typeof id !== "string" || !["stageHistory","recoveryEntries"].includes(kind) || typeof json !== "string") throw new Error("历史明细格式无效");
        const entry = JSON.parse(json);
        if (!details.has(id)) details.set(id, {});
        const data = details.get(id);
        (data[kind] ||= []).push(entry);
      }
    }
    const recoverySheet = wb.Sheets["挽损明细"];
    if (recoverySheet?.["!ref"]) {
      const area = X.utils.decode_range(recoverySheet["!fullref"] || recoverySheet["!ref"]);
      const headings=["工作编号", "实现日期", "金额（元）", "实现方式", "确认依据", "备注", "明细编号（保留）"];
      if (area.e.r>100000 || area.e.c>6 || headings.some((h,c)=>recoverySheet[X.utils.encode_cell({r:0,c})]?.v!==h)) throw new Error("挽损明细表头或范围无效");
      for (let i=1;i<=area.e.r;i++) {
        const cells=headings.map((_,c)=>recoverySheet[X.utils.encode_cell({r:i,c})]);
        if (cells.every(c=>!c || c.v==='')) continue;
        if (cells.some(c=>c?.f)) throw new Error("挽损明细不能含公式");
        const [id,rawDate,amount,method,evidence,note,entryId]=cells.map(c=>c?.v??'');
        let date=rawDate;
        if (typeof date==='number') {
          const parsed=X.SSF.parse_date_code(date,{date1904:!!wb.Workbook?.WBProps?.date1904});
          date=parsed ? `${String(parsed.y).padStart(4,'0')}-${String(parsed.m).padStart(2,'0')}-${String(parsed.d).padStart(2,'0')}` : '';
        }
        if (typeof id!=='string' || !id) throw new Error("分批挽损须填写主表的工作编号，新工作请先导入获得编号再填写明细");
        if (!details.has(id)) details.set(id,{});
        const data=details.get(id);
        (data.recoveryEntries ||= []).push({id:entryId || K.id(),date:String(date).trim(),amount:typeof amount==='number'?amount:Number(amount),method:String(method).trim(),evidence:String(evidence),note:String(note)});
      }
    }
    const ws = wb.Sheets[C.excel.sheetName];
    if (!ws || !ws["!ref"])
      throw new Error(`缺少“${C.excel.sheetName}”工作表或表头`);
    const range = X.utils.decode_range(ws["!fullref"] || ws["!ref"]);
    if (range.e.r > C.limits.maxRecords || range.e.c > columns().length + 20)
      throw new Error("工作表范围过大，请删除多余行列或拆分文件");
    // 直接读取单元格原值：保留数值日期序列与百分比格式，避免 sheet_to_json 根据 z 再转成本地 Date。
    const rows = [];
    for (let ri = 0; ri <= range.e.r; ri++) {
      const row = [];
      for (let ci = 0; ci <= range.e.c; ci++)
        row.push((ws[X.utils.encode_cell({ r: ri, c: ci })] || {}).v ?? "");
      rows.push(row);
    }
    const cols = columns(),
      expected = cols.map((c) => c.label).concat(C.excel.statusLabel);
    const header = rows[0].map((v) => {
      const text = String(v).trim();
      return (
        (cols.find((c) => c.aliases && c.aliases.includes(text)) || {}).label ||
        text
      );
    });
    const errors = [];
    cols.forEach((c) => {
      if (!header.includes(c.label) && !c.importOptional)
        errors.push(`缺少列：${c.label}（请使用模板）`);
    });
    header.forEach((h, i) => {
      if (!expected.includes(h)) errors.push(`第 ${i + 1} 列：未知表头“${h}”`);
      if (header.indexOf(h) !== i) errors.push(`重复表头：${h}`);
    });
    if (errors.length) throw new Error(errors.join("\n"));
    const result = [],
      seen = new Set(),
      now = new Date().toISOString();
    for (let ri = 1; ri < rows.length; ri++) {
      const row = rows[ri];
      const hasFormula = header.some(
        (_, ci) => (ws[X.utils.encode_cell({ r: ri, c: ci })] || {}).f,
      );
      if (row.every((v) => v === "") && !hasFormula) continue;
      const record = { ...(detailSheet ? {stageHistory:[]} : {}), ...(recoverySheet ? {recoveryEntries:[]} : {}) };
      if (hasFormula) errors.push(`第 ${ri + 1} 行：含公式，请先粘贴为值`);
      cols.forEach((c) => {
        const index = header.indexOf(c.label);
        if (index < 0) return;
        let value = row[index] ?? "";
        if (c.type === "number") {
          const cell = ws[X.utils.encode_cell({ r: ri, c: index })] || {};
          const text = String(value).trim();
          const percentFormat =
            typeof cell.z === "string" &&
            /%/.test(cell.z.replace(/\"[^\"]*\"|\\./g, ""));
          if (
            c.key === "progressPercent" &&
            typeof value === "number" &&
            percentFormat
          )
            value = Math.round(value * 100 * 1e8) / 1e8;
          else if (c.key === "progressPercent" && /^\d+(\.\d+)?%$/.test(text))
            value = Number(text.slice(0, -1));
          else
            value =
              text === ""
                ? null
                : /^\d+(\.\d+)?$/.test(text)
                  ? Number(text)
                  : value;
        } else if (c.type === "boolean") {
          if (typeof value === "string") value = value.trim();
          if ([true, 1, "是", "已完成", "true"].includes(value)) value = true;
          else if ([false, 0, "", "否", "未完成", "false"].includes(value))
            value = false;
          else errors.push(`第 ${ri + 1} 行：${c.label}须为是或否`);
        } else if (c.type === "date" && typeof value === "number") {
          const date = X.SSF.parse_date_code(value, {
            date1904: !!(
              wb.Workbook &&
              wb.Workbook.WBProps &&
              wb.Workbook.WBProps.date1904
            ),
          });
          value = date
            ? `${String(date.y).padStart(4, "0")}-${String(date.m).padStart(2, "0")}-${String(date.d).padStart(2, "0")}`
            : String(value);
        } else if (typeof value === "string") {
          // 只规范日期和身份列；进展、跟踪等用户正文保留原空格和换行。
          if (
            ["id", "module", "updatedAt"].includes(c.key) ||
            c.type === "date"
          )
            value = value.trim();
        } else value = String(value);
        if (c.key === "module")
          value =
            (
              [...C.modules, ...(C.legacyModules || [])].find(
                (m) =>
                  m.label === value ||
                  m.id === value ||
                  (m.aliases || []).includes(value),
              ) || {}
            ).id || value;
        record[c.key] = value;
      });
      if (!record.id) record.id = K.id();
      if (!record.updatedAt) record.updatedAt = now;
      if (seen.has(record.id))
        errors.push(`第 ${ri + 1} 行：文件内唯一编号重复`);
      seen.add(record.id);
      Object.assign(record, details.get(record.id) || {});
      if (record.recoveryEntries?.length) record.recoveryActual = record.recoveryEntries.reduce((s,e)=>s+Math.round(e.amount*100),0)/100;
      if (fileTeam) {
        if (record.teamId && record.teamId !== fileTeam) errors.push("记录所属团队与文件团队不一致");
        record.teamId = fileTeam;
      }
      if (options.teamId && record.teamId && record.teamId !== options.teamId) errors.push("文件包含其他团队记录");
      K.validateRecord(record).forEach((e) =>
        errors.push(`第 ${ri + 1} 行：${e}`),
      );
      result.push(record);
    }
    for (const id of details.keys()) if (!seen.has(id)) errors.push("历史明细对应的工作不存在：" + id);
    if (errors.length) throw new Error(errors.join("\n"));
    return result;
  }
  return { columns, workbook, read };
}
