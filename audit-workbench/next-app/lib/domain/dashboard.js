// 只读看板派生量：不修改台账、历史或持久化结构。
export function overdueGroups(records, today) {
  const groups = [{label:'逾期 1–7 天',min:1,max:7,records:[]},{label:'逾期 8–30 天',min:8,max:30,records:[]},{label:'逾期超过 30 天',min:31,max:Infinity,records:[]}];
  for (const r of records) {
    if (r.completed || r.archivedAt || !today || !r.dueDate) continue;
    const days = Math.floor((Date.parse(today+'T00:00:00Z')-Date.parse(r.dueDate+'T00:00:00Z'))/86400000);
    groups.find(g=>days>=g.min && days<=g.max)?.records.push(r);
  }
  for (const g of groups) g.records.sort((a,b)=>a.dueDate.localeCompare(b.dueDate)||a.id.localeCompare(b.id));
  return groups;
}
export function weeklyTrend(snapshots) {
  const latest = new Map();
  for (const s of snapshots) {
    const previous=latest.get(s.week);
    if (!previous || s.savedAt>previous.savedAt || (s.savedAt===previous.savedAt && s.id>previous.id)) latest.set(s.week,s);
  }
  return [...latest.values()].sort((a,b)=>a.week.localeCompare(b.week)).slice(-12).map(s=>{
    const rows=s.records.filter(r=>!r.archivedAt);
    return {id:s.id,week:s.week,asOfDate:s.asOfDate,total:rows.length,normal:rows.filter(r=>r.frozenStatus==='normal').length,overdue:rows.filter(r=>r.frozenStatus==='overdue').length,completed:rows.filter(r=>r.frozenStatus==='completed').length};
  });
}
export function recoveryMonths(records,method='') {
  const months=new Map();
  for (const r of records) if (r.module==='loss-recovery') for (const e of r.recoveryEntries||[]) {
    if (method && e.method!==method) continue;
    const month=e.date.slice(0,7);
    months.set(month,(months.get(month)||0)+Math.round(e.amount*100));
  }
  return [...months].sort(([a],[b])=>a.localeCompare(b)).map(([month,cents])=>({month,amount:cents/100}));
}
