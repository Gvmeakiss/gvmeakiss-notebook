/* 纯业务函数：不访问页面、不读写存储。日期、校验、合并、快照共用这里的口径。 */
export function createCore(root) {
  "use strict";
  const C = root.CONFIG;
  const clone = (value) => JSON.parse(JSON.stringify(value));
  const own = (obj, key) => Object.prototype.hasOwnProperty.call(obj, key);
  const isObject = (x) =>
    x !== null && typeof x === "object" && !Array.isArray(x);
  const localDate = (d = new Date()) =>
    `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  function validDate(s) {
    if (
      typeof s !== "string" ||
      !/^\d{4}-\d{2}-\d{2}$/.test(s) ||
      s < "1900-01-01" ||
      s > "9999-12-31"
    )
      return false;
    const d = new Date(`${s}T12:00:00`);
    return !Number.isNaN(d.getTime()) && localDate(d) === s;
  }
  function validTime(s) {
    return (
      typeof s === "string" &&
      /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(s) &&
      !Number.isNaN(Date.parse(s)) &&
      new Date(s).toISOString() === s
    );
  }
  function id() {
    if (root.crypto && root.crypto.randomUUID) return root.crypto.randomUUID();
    if (!root.crypto || !root.crypto.getRandomValues)
      throw new Error("浏览器不支持安全编号生成，请使用新版 Chrome 或 Edge。");
    return Array.from(root.crypto.getRandomValues(new Uint8Array(16)), (x) =>
      x.toString(16).padStart(2, "0"),
    ).join("");
  }
  const fieldsFor = (module) =>
    C.fields.filter(
      (f) => !f.legacy && (!f.modules || f.modules.includes(module)),
    );
  const percent = (record) =>
    record.completed
      ? 100
      : typeof record.progressPercent === "number"
        ? record.progressPercent
        : null;
  const moduleName = (value) =>
    (C.modules.find((m) => m.id === value) || {}).label || value;
  function status(record, today = localDate()) {
    return record.completed
      ? "completed"
      : record.dueDate < today
        ? "overdue"
        : "normal";
  }
  function monday(date = localDate()) {
    const d = new Date(`${date}T12:00:00`);
    d.setDate(d.getDate() - ((d.getDay() + 6) % 7));
    return localDate(d);
  }
  function validateRecord(r, options = {}) {
    if (!isObject(r)) return ["记录必须是对象"];
    const errors = [];
    const allowed = [
      "id",
      "module",
      "updatedAt",
      ...C.fields.map((f) => f.key),
      ...(options.snapshot ? ["frozenStatus"] : []),
    ];
    Object.keys(r).forEach((k) => {
      if (!allowed.includes(k))
        errors.push(`未知字段 ${k}，请确认配置版本，避免丢失数据`);
    });
    if (typeof r.id !== "string" || !/^[A-Za-z0-9_-]{1,100}$/.test(r.id))
      errors.push("唯一编号须为 1–100 位英文、数字、下划线或短横线");
    if (!C.modules.some((m) => m.id === r.module))
      errors.push("模块不在配置清单中");
    if (!validTime(r.updatedAt)) errors.push("更新时间须为有效 ISO UTC 时间");
    for (const f of C.fields) {
      const active = !f.modules || f.modules.includes(r.module);
      const v = r[f.key];
      if (!active) {
        if (v !== undefined && v !== "" && v !== false)
          errors.push(`${f.label}不适用于此模块`);
        continue;
      }
      if (f.type === "boolean") {
        if (typeof v !== "boolean") errors.push(`${f.label}必须为布尔值`);
      } else if (f.type === "number") {
        if (v === undefined || v === null) {
          if (f.required) errors.push(`${f.label}不能为空`);
        } else if (
          typeof v !== "number" ||
          !Number.isFinite(v) ||
          v < f.min ||
          v > f.max ||
          (f.step === 1 && !Number.isInteger(v))
        ) {
          errors.push(
            `${f.label}须为 ${f.min}–${f.max} 的${f.step === 1 ? "整数" : "数值"}`,
          );
        }
      } else {
        if (v !== undefined && typeof v !== "string") {
          errors.push(`${f.label}必须为文本`);
          continue;
        }
        if (
          (f.required || (f.requiredWhenOpen && !r.completed)) &&
          !String(v || "").trim()
        )
          errors.push(`${f.label}不能为空`);
        if (v && f.type === "date" && !validDate(v))
          errors.push(`${f.label}须为有效 YYYY-MM-DD 日期（1900–9999 年）`);
        if (v && v.length > (f.maxLength || 4000))
          errors.push(`${f.label}超过长度限制`);
      }
    }
    if (
      r.completed &&
      r.progressPercent !== undefined &&
      r.progressPercent !== null &&
      r.progressPercent !== 100
    )
      errors.push("整项已完成时项目进度必须为 100%");
    if (options.snapshot && !own(C.statuses, r.frozenStatus))
      errors.push("快照状态无效");
    return errors;
  }
  function validateRecords(records, options = {}) {
    if (!Array.isArray(records)) return ["记录列表必须是数组"];
    if (records.length > C.limits.maxRecords)
      return [`记录数不能超过 ${C.limits.maxRecords}`];
    const seen = new Set(),
      errors = [];
    records.forEach((r, i) => {
      const prefix = `第 ${i + (options.rowOffset || 1)} 行：`;
      validateRecord(r, options).forEach((e) => errors.push(prefix + e));
      if (r && seen.has(r.id)) errors.push(prefix + "文件内唯一编号重复");
      if (r) seen.add(r.id);
    });
    return errors;
  }
  function emptyState() {
    return { schemaVersion: C.schemaVersion, records: [], snapshots: [] };
  }
  function validateBackup(data) {
    if (!isObject(data) || data.schemaVersion !== C.schemaVersion)
      throw new Error("备份格式或版本不兼容");
    const errors = validateRecords(data.records);
    const allowed = ["schemaVersion", "records", "snapshots", "exportedAt"];
    if (Object.keys(data).some((k) => !allowed.includes(k)))
      errors.push("备份包含未知顶层字段");
    if (data.exportedAt !== undefined && !validTime(data.exportedAt))
      errors.push("备份导出时间无效");
    if (
      !Array.isArray(data.snapshots) ||
      data.snapshots.length > C.limits.maxSnapshots
    )
      errors.push("快照列表无效或超过上限");
    else {
      const ids = new Set();
      data.snapshots.forEach((s, i) => {
        const prefix = `快照 ${i + 1}：`;
        if (!isObject(s)) {
          errors.push(prefix + "格式无效");
          return;
        }
        if (
          Object.keys(s).some(
            (k) =>
              !["id", "week", "savedAt", "asOfDate", "records"].includes(k),
          )
        )
          errors.push(prefix + "包含未知字段");
        if (
          typeof s.id !== "string" ||
          !/^[A-Za-z0-9_-]{1,100}$/.test(s.id) ||
          ids.has(s.id)
        )
          errors.push(prefix + "编号无效或重复");
        ids.add(s.id);
        if (!validDate(s.week) || monday(s.week) !== s.week)
          errors.push(prefix + "所属周必须为周一");
        if (!validTime(s.savedAt) || !validDate(s.asOfDate))
          errors.push(prefix + "保存时间或状态基准日无效");
        validateRecords(s.records, { snapshot: true }).forEach((e) =>
          errors.push(prefix + e),
        );
        if (validDate(s.asOfDate) && Array.isArray(s.records))
          s.records.forEach((r) => {
            if (isObject(r) && r.frozenStatus !== status(r, s.asOfDate))
              errors.push(prefix + "冻结状态与基准日不一致");
          });
      });
    }
    if (errors.length) throw new Error(errors.join("\n"));
    return {
      schemaVersion: C.schemaVersion,
      records: clone(data.records),
      snapshots: clone(data.snapshots),
    };
  }
  // 普通 JSON 合并允许新记录留空编号；完整恢复仍要求备份本身具有完整编号。
  function recordsFromImport(data) {
    const copy = clone(data),
      now = new Date().toISOString();
    if (isObject(copy) && Array.isArray(copy.records))
      copy.records.forEach((r) => {
        if (!isObject(r)) return;
        if (r.id === "" || r.id === undefined) r.id = id();
        if (r.updatedAt === "" || r.updatedAt === undefined) r.updatedAt = now;
      });
    return validateBackup(copy).records;
  }
  // 更新时间不参与业务内容比较，避免导出/导入造成无意义冲突。
  function sameContent(a, b) {
    return ["module", ...C.fields.map((f) => f.key)].every((k) =>
      k === "progressPercent"
        ? percent(a) === percent(b)
        : (a[k] ?? "") === (b[k] ?? ""),
    );
  }
  const naturalKey = (r) => JSON.stringify([r.module, r.name, r.owner]);
  function prepareMerge(current, incoming) {
    const errors = validateRecords(incoming);
    if (errors.length) throw new Error(errors.join("\n"));
    const byId = new Map(current.map((r) => [r.id, r]));
    const naturalIds = new Map();
    [...current, ...incoming].forEach((r) => {
      const key = naturalKey(r);
      if (!naturalIds.has(key)) naturalIds.set(key, new Set());
      naturalIds.get(key).add(r.id);
    });
    return incoming.map((record) => {
      const existing = byId.get(record.id);
      return {
        record: clone(record),
        existing: existing ? clone(existing) : null,
        kind: !existing
          ? "new"
          : sameContent(existing, record)
            ? "same"
            : "conflict",
        warning:
          naturalIds.get(naturalKey(record)).size > 1
            ? "同模块、同名称、同负责人存在其他编号，请核对是否重复工作。"
            : "",
      };
    });
  }
  function applyMerge(current, plan, choices = {}) {
    const map = new Map(current.map((r) => [r.id, clone(r)]));
    plan.forEach((item) => {
      if (
        item.kind === "new" ||
        (item.kind === "conflict" && choices[item.record.id] === "incoming")
      )
        map.set(item.record.id, clone(item.record));
    });
    const result = [...map.values()];
    const errors = validateRecords(result);
    if (errors.length) throw new Error(errors.join("\n"));
    return result;
  }
  function snapshot(records, week = monday(), now = new Date()) {
    if (!validDate(week) || monday(week) !== week)
      throw new Error("请选择所属周的周一日期");
    return {
      id: id(),
      week,
      savedAt: now.toISOString(),
      asOfDate: localDate(now),
      records: records.map((r) => ({
        ...clone(r),
        frozenStatus: status(r, localDate(now)),
      })),
    };
  }
  function filtered(records, filters, frozen = false) {
    const query = (filters.query || "").trim().toLocaleLowerCase();
    return records.filter(
      (r) =>
        (!filters.module || r.module === filters.module) &&
        (!filters.owner || r.owner === filters.owner) &&
        (!filters.status ||
          (frozen ? r.frozenStatus : status(r)) === filters.status) &&
        (!query ||
          [r.id, moduleName(r.module), ...C.fields.map((f) => r[f.key])]
            .join(" ")
            .toLocaleLowerCase()
            .includes(query)),
    );
  }
  function stats(records, frozen = false) {
    const result = {
      total: records.length,
      normal: 0,
      overdue: 0,
      completed: 0,
      modules: {},
    };
    C.modules.forEach((m) => {
      result.modules[m.id] = 0;
    });
    records.forEach((r) => {
      result[frozen ? r.frozenStatus : status(r)]++;
      result.modules[r.module]++;
    });
    return result;
  }
  return {
    clone,
    own,
    localDate,
    validDate,
    validTime,
    id,
    fieldsFor,
    percent,
    moduleName,
    status,
    monday,
    validateRecord,
    validateRecords,
    emptyState,
    validateBackup,
    recordsFromImport,
    sameContent,
    prepareMerge,
    applyMerge,
    snapshot,
    filtered,
    stats,
  };
}
