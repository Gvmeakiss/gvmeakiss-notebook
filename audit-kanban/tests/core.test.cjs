/* 运行：node --test tests/core.test.cjs；仅使用 Node 内置模块和已交付的本地库。 */
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const ctx = { console, crypto: require('node:crypto').webcrypto, Uint8Array, ArrayBuffer, Date };
ctx.window = ctx; vm.createContext(ctx);
for (const f of ['config.js', 'vendor/xlsx.full.min.js', 'core.js', 'excel.js']) vm.runInContext(fs.readFileSync(path.join(root, f), 'utf8'), ctx);
const K = ctx.KanbanCore, E = ctx.KanbanExcel, X = ctx.XLSX;
const r = (changes = {}) => ({ id: 'work-1', module: 'project', name: '采购稽核', owner: '张三', progressPercent: changes.completed ? 100 : 40, tracking: '检查合同', progress: '抽样中', dueDate: '2026-09-07', nextPlan: '核对样本', completed: false, updatedAt: '2026-09-07T01:00:00.000Z', ...changes });
const plain = v => JSON.parse(JSON.stringify(v));
const asBytes = wb => X.write(wb, { type: 'array', bookType: 'xlsx' });
function modifiedSheet(edit) { const wb = E.workbook([r()]); edit(wb.Sheets['工作台账'], wb); return asBytes(wb); }
test('日期状态：昨天红、当天与未来绿、完成优先蓝', () => {
  assert.equal(K.status(r({ dueDate: '2026-09-06' }), '2026-09-07'), 'overdue');
  assert.equal(K.status(r(), '2026-09-07'), 'normal');
  assert.equal(K.status(r({ dueDate: '2026-09-08' }), '2026-09-07'), 'normal');
  assert.equal(K.status(r({ completed: true, dueDate: '2026-09-06' }), '2026-09-07'), 'completed');
});
test('真实日期和闰年边界', () => {
  for (const d of ['2026-02-29', '2026-04-31', '2026-13-01', '2026-1-1', '', '1899-12-31']) assert.equal(K.validDate(d), false, d);
  assert.equal(K.validDate('2028-02-29'), true); assert.equal(K.monday('2027-01-03'), '2026-12-28');
});
test('必填、下一步条件、非法类型及未知字段', () => {
  assert.equal(K.validateRecord(r()).length, 0);
  for (const field of ['name', 'owner', 'dueDate', 'nextPlan']) assert.ok(K.validateRecord(r({ [field]: '' })).length);
  assert.equal(K.validateRecord(r({ nextPlan: '', completed: true })).length, 0);
  for (const change of [{ completed: 'false' }, { unexpected: 'data' }, { module: 'unknown' }, { updatedAt: '2026-02-30T01:00:00.000Z' }, { name: {} }]) assert.ok(K.validateRecord(r(change)).length);
});
test('合并新增、相同跳过、默认保留冲突、明确替换', () => {
  const existing = [r()], incoming = [r({ progress: '完成抽样' }), r({ id: 'work-2', name: '另一个项目' })];
  const p = K.prepareMerge(existing, incoming);
  assert.deepEqual(plain(p.map(x => x.kind)), ['conflict', 'new']);
  assert.equal(K.applyMerge(existing, p)[0].progress, '抽样中');
  assert.equal(K.applyMerge(existing, p, { 'work-1': 'incoming' })[0].progress, '完成抽样');
  assert.equal(existing[0].progress, '抽样中');
  assert.equal(K.prepareMerge(existing, [r({ updatedAt: '2026-09-08T01:00:00.000Z' })])[0].kind, 'same');
  assert.equal(K.applyMerge(existing, K.prepareMerge(existing, [] )).length, 1);
});
test('文件内重复编号阻断，同名不同编号提示', () => {
  assert.throws(() => K.prepareMerge([], [r(), r()]), /重复/);
  assert.ok(K.prepareMerge([r()], [r({ id: 'work-2' })])[0].warning);
});
test('JSON 合并新记录空编号生成，完整恢复不接受空编号', () => {
  const data = { schemaVersion: 1, records: [r({ id: '', updatedAt: '' })], snapshots: [] };
  const row = K.recordsFromImport(data)[0];
  assert.ok(row.id); assert.ok(K.validTime(row.updatedAt)); assert.equal(data.records[0].id, '');
  assert.throws(() => K.validateBackup(data), /唯一编号/);
});
test('快照独立复制、冻结状态、同周多版本', () => {
  const records = [r()], a = K.snapshot(records, '2026-09-07', new Date('2026-09-07T12:00:00')), b = K.snapshot(records, '2026-09-07');
  records[0].progress = '后续改动'; assert.equal(a.records[0].progress, '抽样中');
  assert.equal(a.records[0].frozenStatus, 'normal'); assert.equal(K.status(a.records[0], '2026-09-08'), 'overdue');
  assert.notEqual(a.id, b.id); assert.throws(() => K.snapshot(records, '2026-09-08'), /周一/);
  assert.equal(K.validateBackup({ schemaVersion: 1, records: [r()], snapshots: [a, b] }).snapshots.length, 2);
});
test('损坏备份和快照严格校验', () => {
  assert.throws(() => K.validateBackup({ schemaVersion: 2 }), /版本/);
  assert.throws(() => K.validateBackup({ schemaVersion: 1, records: [r()], snapshots: {} }), /快照/);
  const s = K.snapshot([r()], '2026-09-07', new Date('2026-09-07T12:00:00')); s.records[0].frozenStatus = 'overdue';
  assert.throws(() => K.validateBackup({ schemaVersion: 1, records: [], snapshots: [s] }), /不一致/);
});
test('筛选与统计口径一致，历史使用冻结状态', () => {
  const rows = [r(), r({ id: 'work-2', owner: '李四', module: 'other', completed: true })];
  assert.equal(K.filtered(rows, { query: '采购', owner: '李四', module: 'other', status: 'completed' }).length, 1);
  const counts = K.stats(rows); assert.equal(counts.total, 2); assert.equal(counts.completed, 1); assert.equal(counts.modules.other, 1);
  assert.equal(K.stats([{ ...r(), frozenStatus: 'overdue' }], true).overdue, 1);
});
test('Excel 往返所有字段保真，文字不成为公式', () => {
  const original = r({ name: '=HYPERLINK("https://example.invalid")', progress: ' <img src=x onerror=alert(1)>\n', tracking: '@SUM(A1)', nextPlan: '+cmd|test' });
  const wb = E.workbook([original]); assert.equal(wb.Sheets['工作台账'].C2.t, 's'); assert.equal(wb.Sheets['工作台账'].C2.f, undefined);
  assert.equal(wb.Sheets['工作台账'].H2.t, 'n'); assert.equal(wb.Sheets['工作台账'].H2.z, 'yyyy-mm-dd');
  assert.deepEqual(plain(E.read(asBytes(wb))), [original]);
  assert.equal(E.read(asBytes(E.workbook([]))).length, 0);
});
test('Excel 缺失编号生成、日期文本、完成标记空白按否', () => {
  const bytes = modifiedSheet(ws => { ws.A2 = { t: 's', v: '' }; ws.H2 = { t: 's', v: '2026-09-07' }; ws.J2 = { t: 's', v: '' }; ws.K2 = { t: 's', v: '' }; });
  const row = E.read(bytes)[0]; assert.ok(row.id); assert.equal(row.completed, false); assert.ok(K.validTime(row.updatedAt));
});
test('Excel 无效日期、非法完成值、公式、缺失列整批阻断', () => {
  assert.throws(() => E.read(modifiedSheet(ws => { ws.H2 = { t: 's', v: '2026-02-30' }; })), /第 2 行.*日期/);
  assert.throws(() => E.read(modifiedSheet(ws => { ws.J2 = { t: 's', v: '也许' }; })), /第 2 行.*是否完成/);
  assert.throws(() => E.read(modifiedSheet(ws => { ws.C2 = { t: 's', v: 'x', f: 'A2' }; })), /含公式/);
  assert.throws(() => E.read(modifiedSheet(ws => { ws.C1 = { t: 's', v: '新名字' }; })), /缺少列/);
  assert.throws(() => E.read(new Uint8Array([1, 2, 3]).buffer), /不是有效/);
});
test('Excel 1900/1904 日期系统与早期日期边界', () => {
  for (const date of ['1900-01-01', '1900-02-28', '1900-03-01', '2028-02-29', '9999-12-31']) {
    assert.equal(E.read(asBytes(E.workbook([r({ dueDate: date })])))[0].dueDate, date);
  }
  const bytes = modifiedSheet((ws, wb) => { ws.H2 = { t: 'n', v: 0, z: 'yyyy-mm-dd' }; wb.Workbook = { WBProps: { date1904: true } }; });
  assert.equal(E.read(bytes)[0].dueDate, '1904-01-01');
});
test('Excel 重复编号按实际行号报告', () => {
  assert.throws(() => E.read(asBytes(E.workbook([r(), r()]))), /第 3 行.*重复/);
});
test('配置扩展字段支持模块差异、校验和 Excel 往返', () => {
  ctx.CONFIG.fields.push({ key: 'riskMemo', label: '风险备注', type: 'textarea', modules: ['risk-topic'] });
  try {
    const row = r({ module: 'risk-topic', riskMemo: '补充线索' });
    assert.ok(K.fieldsFor('risk-topic').some(f => f.key === 'riskMemo'));
    assert.ok(!K.fieldsFor('project').some(f => f.key === 'riskMemo'));
    assert.equal(K.validateRecord(row).length, 0);
    assert.ok(K.validateRecord(r({ riskMemo: '不适用字段' })).length);
    assert.equal(E.read(asBytes(E.workbook([row])))[0].riskMemo, '补充线索');
  } finally { ctx.CONFIG.fields.pop(); }
});

test('手填百分比边界、完成联动、未知进度不伪造', () => {
  for (const n of [0, 1, 60, 99, 100]) assert.equal(K.validateRecord(r({ progressPercent: n })).length, 0);
  for (const n of [-1, 101, 0.5, '60', Infinity]) assert.ok(K.validateRecord(r({ progressPercent: n })).length);
  assert.equal(K.percent(r({ progressPercent: null })), null);
  assert.equal(K.percent(r({ progressPercent: undefined })), null);
  assert.equal(K.percent(r({ completed: true, progressPercent: undefined })), 100);
  assert.ok(K.validateRecord(r({ completed: true, progressPercent: 60 })).length);
  assert.equal(K.status(r({ progressPercent: 100, completed: false }), '2026-09-07'), 'normal');
});
test('旧版 Excel 无百分比、原工作跟踪列仍可导入', () => {
  const cols = E.columns().filter(c => c.key !== 'progressPercent');
  const old = r(); delete old.progressPercent;
  const rows = [cols.map(c => c.key === 'tracking' ? '工作跟踪' : c.label), cols.map(c => c.key === 'module' ? '项目' : c.type === 'boolean' ? '否' : old[c.key])];
  const wb = X.utils.book_new(); X.utils.book_append_sheet(wb, X.utils.aoa_to_sheet(rows), '工作台账');
  const record = E.read(asBytes(wb))[0];
  assert.equal(record.tracking, '检查合同'); assert.equal(K.percent(record), null);
  assert.equal(K.validateBackup({ schemaVersion: 1, records: [old], snapshots: [] }).records[0].tracking, '检查合同');
});
test('Excel 百分比数值往返及非法进度整批阻断', () => {
  assert.equal(E.read(asBytes(E.workbook([r({ progressPercent: 75 })])))[0].progressPercent, 75);
  assert.throws(() => E.read(modifiedSheet(ws => { ws.E2 = { t: 'n', v: 101 }; })), /第 2 行.*项目进度/);
});

test('Excel 隐藏编号与更新时间，落盘后仍完整保留并可合并', () => {
  const wb = E.workbook([r()]);
  const stored = X.read(asBytes(wb), { type: 'array', cellStyles: true });
  const sheet = stored.Sheets['工作台账'];
  assert.equal(sheet['!cols'][0].hidden, true);
  const updated = E.columns().findIndex(c => c.key === 'updatedAt');
  assert.equal(sheet['!cols'][updated].hidden, true);
  const roundTrip = E.read(asBytes(wb));
  assert.equal(roundTrip[0].id, r().id); assert.equal(roundTrip[0].updatedAt, r().updatedAt);
  assert.equal(K.prepareMerge([r()], roundTrip)[0].kind, 'same');
});
