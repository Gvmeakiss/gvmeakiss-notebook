/* 新增业务字段与纯函数。所有金额以元保存，合计以分计算；旧数据缺省值保持未知。 */
export const collaborationStatuses = ['推进中','等待资料','等待业务反馈','等待复核','暂缓'];
export const enhancementFields = [
  { key: 'collaborationStatus', label: '协作状态', type: 'text', maxLength: 30 },
  { key: 'followUpDate', label: '跟进日期', type: 'date' },
  { key: 'remarks', label: '备注', type: 'textarea', maxLength: 2000 },
  { key: 'archivedAt', label: '归档时间（系统保留）', type: 'text', maxLength: 40, hidden: true },
  { key: 'teamId', label: '所属团队编号', type: 'text', maxLength: 100, hidden: true },
  { key: 'stageHistory', label: '历次阶段记录（系统保留）', type: 'json', hidden: true },
  { key: 'attention', label: '关注级别', type: 'text', maxLength: 20 },
  { key: 'blocker', label: '当前阻碍', type: 'textarea', maxLength: 2000 },
  { key: 'supportNeeded', label: '需要协调', type: 'textarea', maxLength: 2000 },
  { key: 'outcomeSummary', label: '成果摘要', type: 'textarea', maxLength: 4000 },
  { key: 'outcomeStatus', label: '成果状态', type: 'text', maxLength: 30 },
  { key: 'evidence', label: '成果确认依据', type: 'textarea', maxLength: 2000 },
  { key: 'confirmedDate', label: '成果确认日期', type: 'date' },
  { key: 'relatedRecordIds', label: '关联工作编号', type: 'text', maxLength: 2000 },
  { key: 'outcomeCount', label: '成果数量', type: 'number', min: 0, max: 1000000, step: 1 },
  { key: 'coverage', label: '成果覆盖范围', type: 'text', maxLength: 500 },
  { key: 'letterSentDate', label: '发函日期', type: 'date' },
  { key: 'replyDueDate', label: '回复期限', type: 'date' },
  { key: 'replyDate', label: '实际回复日期', type: 'date' },
  { key: 'recoveryExpected', label: '应挽损金额（元）', type: 'number', min: 0, max: 100000000000, step: 0.01 },
  { key: 'recoveryActual', label: '累计实际挽损（元）', type: 'number', min: 0, max: 100000000000, step: 0.01 },
  { key: 'recoveryMethod', label: '累计挽损实现方式', type: 'text', maxLength: 30 },
  { key: 'recoveryKey', label: '挽损成果编号', type: 'text', maxLength: 100 },
  { key: 'recoveryEntries', label: '分批挽损明细（系统保留）', type: 'json', hidden: true },
].map(f => ({ ...f, importOptional: true }));
export const outcomeLabels = {
  project: ['已确认重要问题', '建议采纳、整改落实及效果'],
  'risk-topic': ['已应用议题', '研究成果及采纳应用情况'],
  'risk-system': ['已上线规则', '有效线索与规则运行效果'],
  'three-promotions': ['已落地措施', '具体推动事项及效果'],
  'three-letters': ['已落实事项', '回复及后续落实情况'],
  'loss-recovery': ['挽损成果', '成果说明'],
  other: ['成果数量', '成果类型及说明'],
};
export const stageKeys = ['previousStageContent','previousStageCompletedDate','currentStageTask','currentStageDueDate','progress','nextPlan'];
const copy = x => JSON.parse(JSON.stringify(x));
const stable = x => JSON.stringify(x, Object.keys(x).sort());
const stageData = r => Object.fromEntries(stageKeys.map(k => [k, r[k] || '']));
const hasStage = r => stageKeys.some(k => r[k]);
export function setArchived(record, archived, now = new Date().toISOString()) {
  if (archived && !record.completed) throw new Error('请先确认整项工作已完成，再归档');
  if (!!record.archivedAt === archived) return copy(record);
  return { ...copy(record), archivedAt: archived ? now : '', updatedAt: now };
}
export function combineHistory(a = [], b = []) {
  const map = new Map(a.map(h => [h.id, copy(h)]));
  for (const h of b) {
    if (map.has(h.id) && stable(map.get(h.id)) !== stable(h)) throw new Error('同编号阶段历史内容不一致，不能改写已留存历史');
    map.set(h.id, copy(h));
  }
  return [...map.values()].sort((x,y) => x.recordedAt.localeCompare(y.recordedAt) || x.id.localeCompare(y.id));
}
export function retainHistory(previous, next, makeId, now = new Date().toISOString(), reason = '修改前留存') {
  const result = copy(next);
  const history = combineHistory(previous?.stageHistory, next.stageHistory);
  if (previous && hasStage(previous) && stable(stageData(previous)) !== stable(stageData(next))) {
    const data = stageData(previous);
    // 显式阶段推进已归档同一内容时，不重复追加。
    if (!history.some(h => !(previous.stageHistory || []).some(p => p.id === h.id) && stable(stageData(h)) === stable(data)))
      history.push({ id: makeId(), recordedAt: now, reason, ...data });
  }
  if (history.length) result.stageHistory = history;
  return result;
}
export function advanceStage(record, completedDate, makeId, now = new Date().toISOString()) {
  if (record.completed) throw new Error('整项工作已完成，请先取消完成标记');
  if (!record.currentStageTask?.trim() && !record.progress?.trim()) throw new Error('请先填写本阶段任务或进展');
  const next = { ...record, previousStageContent: [record.currentStageTask, record.progress].filter(Boolean).join('\n'), previousStageCompletedDate: completedDate, currentStageTask: record.nextPlan || '', currentStageDueDate: '', progress: '', nextPlan: '', updatedAt: now };
  return retainHistory(record, next, makeId, now, '完成阶段并推进');
}
const validAmount = n => typeof n === 'number' && Number.isFinite(n) && n >= 0 && n <= 100000000000 && Math.abs(n * 100 - Math.round(n * 100)) < 0.001;
export function actualAmount(r) {
  if (Array.isArray(r.recoveryEntries) && r.recoveryEntries.length) return r.recoveryEntries.reduce((s,e) => s + Math.round(e?.amount * 100), 0) / 100;
  return typeof r.recoveryActual === 'number' ? r.recoveryActual : null;
}
export function validateEnhancements(r, validDate, validTime) {
  const errors = [];
  if (r.collaborationStatus && !collaborationStatuses.includes(r.collaborationStatus)) errors.push('协作状态无效');
  if (r.archivedAt && (!validTime(r.archivedAt) || !r.completed)) errors.push('仅已完成事项可归档，归档时间须有效');
  if (r.teamId && !/^[A-Za-z0-9_-]{1,100}$/.test(r.teamId)) errors.push('所属团队编号无效');
  if (r.attention && !['普通','重点','紧急'].includes(r.attention)) errors.push('关注级别无效');
  if (r.outcomeStatus && !['待确认','已确认','研究中','形成方案','被采纳','已应用','推进中','已落实','待回复','已回复'].includes(r.outcomeStatus)) errors.push('成果状态无效');
  for (const k of ['recoveryExpected','recoveryActual']) if (r[k] != null && !validAmount(r[k])) errors.push('挽损金额须为非负金额，最多两位小数');
  if (r.recoveryMethod && !['资金追回','核减支付','其他已确认实现'].includes(r.recoveryMethod)) errors.push('挽损实现方式无效');
  if (r.outcomeStatus === '已确认' && (!r.evidence?.trim() || !r.confirmedDate)) errors.push('已确认成果须填写确认依据和确认日期');
  if (r.module === 'loss-recovery' && actualAmount(r) > 0) {
    if (!r.recoveryKey?.trim()) errors.push('实际挽损大于零时须填写唯一挽损成果编号');
    if (!r.recoveryEntries?.length && (!r.evidence?.trim() || !r.confirmedDate || !r.recoveryMethod)) errors.push('累计实际挽损须填写实现方式、确认依据和日期');
  }
  if (r.stageHistory !== undefined) {
    if (!Array.isArray(r.stageHistory) || r.stageHistory.length > 2000) errors.push('阶段历史须为列表且不超过2000条');
    else {
      const ids = new Set();
      for (const h of r.stageHistory) {
        if (!h || typeof h !== 'object' || Array.isArray(h)) { errors.push('阶段历史格式错误'); continue; }
        if (Object.keys(h).some(k => !['id','recordedAt','reason',...stageKeys].includes(k))) errors.push('阶段历史含未知字段');
        if (typeof h.id !== 'string' || !/^[A-Za-z0-9_-]{1,100}$/.test(h.id) || ids.has(h.id)) errors.push('阶段历史编号无效或重复');
        ids.add(h.id);
        if (!validTime(h.recordedAt)) errors.push('阶段留存时间无效');
        if (typeof h.reason !== 'string' || h.reason.length > 100) errors.push('阶段历史来源无效');
        for (const k of stageKeys) if (h[k] !== undefined && (typeof h[k] !== 'string' || h[k].length > 4000)) errors.push('阶段历史内容无效');
        for (const k of ['previousStageCompletedDate','currentStageDueDate']) if (h[k] && !validDate(h[k])) errors.push('阶段历史日期无效');
      }
    }
  }
  if (r.recoveryEntries !== undefined) {
    if (!Array.isArray(r.recoveryEntries) || r.recoveryEntries.length > 1000) errors.push('挽损明细须为列表且不超过1000条');
    else {
      const ids = new Set();
      for (const e of r.recoveryEntries) {
        if (!e || typeof e !== 'object' || Array.isArray(e)) { errors.push('挽损明细格式错误'); continue; }
        if (Object.keys(e).some(k => !['id','date','amount','method','evidence','note'].includes(k))) errors.push('挽损明细含未知字段');
        if (typeof e.id !== 'string' || !/^[A-Za-z0-9_-]{1,100}$/.test(e.id) || ids.has(e.id)) errors.push('挽损明细编号无效或重复');
        ids.add(e.id);
        if (!validDate(e.date) || !validAmount(e.amount) || e.amount <= 0) errors.push('挽损明细日期或金额无效');
        if (!['资金追回','核减支付','其他已确认实现'].includes(e.method)) errors.push('挽损明细实现方式无效');
        if (typeof e.evidence !== 'string' || !e.evidence.trim() || e.evidence.length > 2000) errors.push('每笔实际挽损须有确认依据');
        if (e.note !== undefined && (typeof e.note !== 'string' || e.note.length > 2000)) errors.push('挽损明细备注无效');
      }
      if (r.recoveryEntries.length && r.recoveryActual != null && Math.round(r.recoveryActual * 100) !== Math.round(actualAmount(r) * 100)) errors.push('累计实际挽损与分批明细合计不一致');
    }
  }
  return errors;
}
export function validateRecoveryKeys(records) {
  const seen = new Set(), errors = [];
  for (const r of records) if (r && r.module === 'loss-recovery' && r.recoveryKey?.trim()) {
    const key = r.recoveryKey.trim().toLocaleUpperCase();
    if (seen.has(key)) errors.push('挽损成果编号重复：' + r.recoveryKey + '；同一成果请保留一项并关联来源工作');
    seen.add(key);
  }
  return errors;
}
export function recoveryStats(records, period = '', method = '') {
  const items = records.filter(r => r.module === 'loss-recovery');
  let expected = 0, actual = 0, expectedCount = 0, actualCount = 0, pairedExpected = 0, pairedActual = 0, pairedCount = 0, periodAmount = 0, undatedCount = 0;
  for (const r of items) {
    const a = actualAmount(r), e = r.recoveryExpected;
    if (typeof e === 'number') { expected += Math.round(e*100); expectedCount++; }
    if (a !== null) { actual += Math.round(a*100); actualCount++; }
    if (typeof e === 'number' && a !== null) { pairedExpected += Math.round(e*100); pairedActual += Math.round(a*100); pairedCount++; }
    if (r.recoveryEntries?.length) {
      for (const row of r.recoveryEntries) if ((!period || row.date.startsWith(period)) && (!method || row.method === method)) periodAmount += Math.round(row.amount*100);
    } else if (a > 0) undatedCount++;
  }
  return { count:items.length, expected:expected/100, actual:actual/100, expectedCount, actualCount, pairedCount, ratio:pairedExpected > 0 ? pairedActual*100/pairedExpected : null, remaining:(pairedExpected-pairedActual)/100, periodAmount:periodAmount/100, undatedCount };
}
export function compareSnapshot(current, baseline) {
  // Excel 的列顺序及新版本补出的空字段不应被识别为业务变更。
  const canonical = value => Array.isArray(value) ? value.map(canonical) : value && typeof value === 'object'
    ? Object.fromEntries(Object.entries(value).filter(([k,v]) => !['updatedAt','frozenStatus','teamId'].includes(k) && v !== '' && v != null && !(Array.isArray(v) && !v.length)).sort(([a],[b])=>a.localeCompare(b)).map(([k,v])=>[k,canonical(v)])) : value;
  const old = new Map(baseline.map(r => [r.id,r])), now = new Set(current.map(r => r.id));
  const result = { added:[], completed:[], dueChanged:[], updated:[], absent:[] };
  for (const r of current) {
    const p = old.get(r.id);
    if (!p) result.added.push(r);
    else {
      if (!p.completed && r.completed) result.completed.push(r);
      if (p.dueDate !== r.dueDate) result.dueChanged.push(r);
      if (JSON.stringify(canonical(p)) !== JSON.stringify(canonical(r))) result.updated.push(r);
    }
  }
  result.absent = baseline.filter(r => !now.has(r.id));
  return result;
}
export function attentionReasons(r, today) {
  if (r.completed || r.archivedAt) return [];
  const days = Math.floor((Date.parse(today+'T12:00:00Z')-Date.parse(r.updatedAt))/86400000);
  const until = Math.round((Date.parse(r.dueDate+'T12:00:00Z')-Date.parse(today+'T12:00:00Z'))/86400000);
  return [r.attention === '紧急' || r.attention === '重点' ? r.attention : '', r.dueDate < today ? '已逾期' : until <= 7 ? '7天内到期' : '', days >= 14 ? '14天未更新' : '', r.blocker ? '存在阻碍' : '', r.supportNeeded ? '需要协调' : '', r.followUpDate && r.followUpDate <= today ? '跟进到期' : '', r.module === 'three-letters' && r.replyDueDate && !r.replyDate && r.replyDueDate < today ? '回复超期' : ''].filter(Boolean);
}
