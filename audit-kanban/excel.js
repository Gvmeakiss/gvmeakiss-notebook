/* Excel 边界适配：只有此文件依赖本地 SheetJS。其他业务逻辑不依赖 Excel 库。 */
(function (root) {
  'use strict';
  const C = root.CONFIG, K = root.KanbanCore;
  function columns() {
    return [{ key: 'id', label: C.excel.idLabel }, { key: 'module', label: C.excel.moduleLabel },
      ...C.fields, { key: 'updatedAt', label: C.excel.updatedLabel }];
  }
  function workbook(records, options = {}) {
    const X = root.XLSX;
    if (!X) throw new Error('Excel 库未加载，请检查 vendor 文件夹是否完整');
    const cols = columns().filter(c => !c.legacy || records.some(r => r[c.key]));
    const rows = [cols.map(c => c.label).concat(C.excel.statusLabel)];
    for (const r of records) {
      rows.push(cols.map(c => {
        if (c.key === 'module') return K.moduleName(r.module);
        if (c.type === 'boolean') return r[c.key] ? '是' : '否';
        if (c.key === 'progressPercent') return K.percent(r) ?? '';
        if (c.type === 'date' && r[c.key]) {
          // 日期使用数值序列与显示格式；用户文字始终由 aoa_to_sheet 写成字符串单元格。
          const serial = (Date.UTC(...r[c.key].split('-').map((n, i) => +n - (i === 1 ? 1 : 0))) - Date.UTC(1899, 11, 30)) / 86400000;
          return { t: 'n', v: serial < 61 ? serial - 1 : serial, z: 'yyyy-mm-dd' };
        }
        return String(r[c.key] ?? '');
      }).concat(C.statuses[options.frozen ? r.frozenStatus : K.status(r)].label));
    }
    const ws = X.utils.aoa_to_sheet(rows);
    // 编号和更新时间仍随文件流转，但默认隐藏，让填报同事只看到业务字段。
    ws['!cols'] = cols.map(c => ({ wch: c.type === 'textarea' ? 45 : c.key === 'id' || c.key === 'updatedAt' ? 38 : 22,
      hidden: c.key === 'id' || c.key === 'updatedAt' })).concat({ wch: 20 });
    ws['!autofilter'] = { ref: X.utils.encode_range({ r: 0, c: 0 }, { r: Math.max(0, rows.length - 1), c: cols.length }) };
    const wb = X.utils.book_new();
    X.utils.book_append_sheet(wb, ws, C.excel.sheetName);
    const instructions = [
      ['填写说明', '要求'], ['唯一编号', '新工作可留空；更新已有工作时请保留编号，不要重新生成。'],
      ['模块', C.modules.map(m => m.label).join('、')], ['预计交付日期', '填写 Excel 日期或 YYYY-MM-DD，例如 2026-09-30。'],
      ['项目进度（%）', '填写 0–100 整数，如 60（不是 0.6）。空白表示未填写，整项已完成时填 100。'],
      ['是否完成', '填写 是／否；空白按否处理。完成指整项工作完成。'], ['下一步计划', '未完成时必填。'],
      ['更新时间', '已有记录保留原值；新工作可留空，导入时生成。'], ['实际状态（只读）', '根据完成标记与日期计算，导入不读取此列。'],
      ['合并', '同编号不同内容需要汇总人逐条选择，不按更新时间自动覆盖。'],
      ['注意', `只读取“${C.excel.sheetName}”工作表；其他表仅供说明。禁止数据区公式，请粘贴为值。`]
    ];
    const help = X.utils.aoa_to_sheet(instructions);
    help['!cols'] = [{ wch: 24 }, { wch: 95 }];
    X.utils.book_append_sheet(wb, help, '填写说明');
    return wb;
  }
  function read(buffer) {
    const X = root.XLSX;
    if (!X) throw new Error('Excel 库未加载');
    const bytes = new Uint8Array(buffer);
    if (bytes[0] !== 0x50 || bytes[1] !== 0x4b) throw new Error('不是有效的 .xlsx 文件，请勿仅修改扩展名');
    const wb = X.read(buffer, { type: 'array', cellDates: false, cellFormula: true, sheetRows: C.limits.maxRecords + 3 });
    const ws = wb.Sheets[C.excel.sheetName];
    if (!ws || !ws['!ref']) throw new Error(`缺少“${C.excel.sheetName}”工作表或表头`);
    const range = X.utils.decode_range(ws['!fullref'] || ws['!ref']);
    if (range.e.r > C.limits.maxRecords || range.e.c > columns().length + 20) throw new Error('工作表范围过大，请删除多余行列或拆分文件');
    const rows = X.utils.sheet_to_json(ws, { header: 1, defval: '', raw: true, blankrows: true, range: 0 });
    const cols = columns(), expected = cols.map(c => c.label).concat(C.excel.statusLabel);
    const header = rows[0].map(v => {
      const text = String(v).trim();
      return (cols.find(c => c.aliases && c.aliases.includes(text)) || {}).label || text;
    });
    const errors = [];
    cols.forEach(c => { if (!header.includes(c.label) && !c.importOptional) errors.push(`缺少列：${c.label}（请使用模板）`); });
    header.forEach((h, i) => {
      if (!expected.includes(h)) errors.push(`第 ${i + 1} 列：未知表头“${h}”`);
      if (header.indexOf(h) !== i) errors.push(`重复表头：${h}`);
    });
    if (errors.length) throw new Error(errors.join('\n'));
    const result = [], seen = new Set(), now = new Date().toISOString();
    for (let ri = 1; ri < rows.length; ri++) {
      const row = rows[ri];
      const hasFormula = header.some((_, ci) => (ws[X.utils.encode_cell({ r: ri, c: ci })] || {}).f);
      if (row.every(v => v === '') && !hasFormula) continue;
      const record = {};
      if (hasFormula) errors.push(`第 ${ri + 1} 行：含公式，请先粘贴为值`);
      cols.forEach(c => {
        const index = header.indexOf(c.label);
        if (index < 0) return;
        let value = row[index] ?? '';
        if (c.type === 'number') {
          const text = String(value).trim();
          value = text === '' ? null : /^\d+(\.\d+)?$/.test(text) ? Number(text) : value;
        } else if (c.type === 'boolean') {
          if (typeof value === 'string') value = value.trim();
          if ([true, 1, '是', '已完成', 'true'].includes(value)) value = true;
          else if ([false, 0, '', '否', '未完成', 'false'].includes(value)) value = false;
          else errors.push(`第 ${ri + 1} 行：${c.label}须为是或否`);
        } else if (c.type === 'date' && typeof value === 'number') {
          const date = X.SSF.parse_date_code(value, { date1904: !!(wb.Workbook && wb.Workbook.WBProps && wb.Workbook.WBProps.date1904) });
          value = date ? `${String(date.y).padStart(4, '0')}-${String(date.m).padStart(2, '0')}-${String(date.d).padStart(2, '0')}` : String(value);
        } else if (typeof value === 'string') {
          // 只规范日期和身份列；进展、跟踪等用户正文保留原空格和换行。
          if (['id', 'module', 'updatedAt'].includes(c.key) || c.type === 'date') value = value.trim();
        }
        else value = String(value);
        if (c.key === 'module') value = (C.modules.find(m => m.label === value || m.id === value) || {}).id || value;
        record[c.key] = value;
      });
      if (!record.id) record.id = K.id();
      if (!record.updatedAt) record.updatedAt = now;
      if (seen.has(record.id)) errors.push(`第 ${ri + 1} 行：文件内唯一编号重复`);
      seen.add(record.id);
      K.validateRecord(record).forEach(e => errors.push(`第 ${ri + 1} 行：${e}`));
      result.push(record);
    }
    if (errors.length) throw new Error(errors.join('\n'));
    return result;
  }
  root.KanbanExcel = { columns, workbook, read };
})(window);
