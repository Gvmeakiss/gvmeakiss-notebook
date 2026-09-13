"use client";
import type {AuditRecord,Snapshot} from '@/types/audit';
import {overdueGroups,weeklyTrend} from '@/lib/domain/dashboard.js';
export function OverdueAging({records,today,onDetail}:{records:AuditRecord[];today:string;onDetail:(r:AuditRecord)=>void}) {
  const groups=overdueGroups(records,today), max=Math.max(1,...groups.map(g=>g.records.length));
  return <details className="insight-section"><summary>逾期时长分布</summary>
    <p className="muted">当前筛选内未归档、未完成事项 · 按整体交付日期计算，当天到期不算逾期。</p>
    <div className="aging-grid">{groups.map(g=><details key={g.label} className="aging-group"><summary>{g.label}<strong>{g.records.length} 项</strong><span className="chart-track" aria-hidden="true"><span className="chart-fill overdue" style={{width:`${g.records.length/max*100}%`}}/></span></summary>
      {g.records.length?g.records.map((r:AuditRecord)=><p key={r.id}><button className="text-button" onClick={()=>onDetail(r)}>{r.name}</button><small>{r.owner} · 交付 {r.dueDate}</small></p>):<p className="muted">此分组暂无事项</p>}
    </details>)}</div>
  </details>;
}
export function HistoryTrend({snapshots,onSelect}:{snapshots:Snapshot[];onSelect:(id:string)=>void}) {
  const rows=weeklyTrend(snapshots), max=Math.max(1,...rows.map(r=>r.total));
  return <details className="insight-section"><summary>近 12 个留档周 · 工作状态趋势</summary>
    <p className="muted">团队全部事项，每周取最后一次留档；不受当前列表筛选影响。使用当时状态，排除当时已归档事项。缺失周不补零；数量变化可能包含新增或归档。</p>
    {!rows.length?<p>暂无历史周报，留档后显示趋势。</p>:<><div className="chart-legend"><span className="normal">● 未逾期</span><span className="overdue">● 已逾期</span><span className="completed">● 已完成</span><span>单位：项 · 共同刻度 0–{max}</span></div>
      {rows.map(r=><button key={r.id} className="trend-row" onClick={()=>onSelect(r.id)} aria-label={`${r.week} 周报：未逾期 ${r.normal}，已逾期 ${r.overdue}，已完成 ${r.completed}，共 ${r.total} 项`}>
        <span>{r.week}<small>状态日 {r.asOfDate}</small></span><span className="chart-track" aria-hidden="true">{(['normal','overdue','completed'] as const).map(k=><span key={k} className={`chart-fill ${k}`} style={{width:`${r[k]/max*100}%`}}/>)}</span><span>{r.total} 项<small>未逾期 {r.normal} / 逾期 {r.overdue} / 完成 {r.completed}</small></span>
      </button>)}<small className="muted">点击任一周查看对应的完整历史周报。</small></>}
  </details>;
}
