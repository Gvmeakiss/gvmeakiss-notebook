"use client";
import { useState, useEffect } from 'react';
import type { AuditRecord, AuditState } from '@/types/audit';
import { actualAmount, recoveryStats, compareSnapshot, attentionReasons, outcomeLabels } from '@/lib/domain/enhancements.js';
export const money = (n:number|null) => n===null ? '待确认' : n.toLocaleString('zh-CN',{minimumFractionDigits:2,maximumFractionDigits:2})+' 元';
export function RecoverySummary({records,includesArchived=false}: {records:AuditRecord[];includesArchived?:boolean}) {
  records=records.filter(r=>r.module==='loss-recovery');
  const [selectedPeriod,setPeriod]=useState(''),[method,setMethod]=useState('');
  const periods=Array.from(new Set(records.flatMap(r=>(r.recoveryEntries||[]).flatMap(e=>[e.date.slice(0,4),e.date.slice(0,7)])))).sort().reverse();
  const period=periods.includes(selectedPeriod)?selectedPeriod:'';
  useEffect(()=>{if(selectedPeriod && !period) setPeriod('');},[selectedPeriod,period]);
  const s=recoveryStats(records,period,method);
  if (!s.count) return null;
  return <details className="insight-section" aria-label="挽损贡献"><summary>挽损贡献</summary><p className="muted">当前筛选事项截至当前版本的累计值{includesArchived?'（含归档成果）':''} · 单位：元</p>
    <div className="value-grid"><div><span>应挽损金额</span><strong>{money(s.expectedCount?s.expected:null)}</strong><small>{s.expectedCount}/{s.count} 项已填写</small></div><div><span>实际挽损金额</span><strong>{money(s.actualCount?s.actual:null)}</strong><small>{s.actualCount}/{s.count} 项已填写</small></div><div><span>挽损比例</span><strong>{s.ratio===null?'—':s.ratio.toFixed(1)+'%'}</strong><small>两项金额均已填写的 {s.pairedCount} 项合计计算</small></div><div><span>尚未实现挽损</span><strong>{money(s.pairedCount?s.remaining:null)}</strong><small>同口径 {s.pairedCount} 项；负值请核对</small></div></div>
    {s.pairedCount<s.count && <p className="notice">部分事项金额待确认，比例仅覆盖完整填写的事项，不能代表全部挽损工作。</p>}
    <details><summary>分批挽损 · 月度与年度统计</summary><div className="tools">
      <label>统计期间<select aria-label="挽损统计期间" value={period} onChange={e=>setPeriod(e.target.value)}><option value="">全部日期</option>{periods.map(p=><option key={p}>{p}</option>)}</select></label>
      <label>实现方式<select aria-label="统计实现方式" value={method} onChange={e=>setMethod(e.target.value)}><option value="">全部方式</option>{['资金追回','核减支付','其他已确认实现'].map(v=><option key={v}>{v}</option>)}</select></label>
      <strong>本期已记录实际挽损：{money(s.periodAmount)}</strong></div>
      <p className="muted">按分批明细实际实现日期统计；{s.undatedCount} 项仅有累计值，不纳入期间统计。累计值和明细不重复相加。</p>
      <div className="table-scroll"><table><thead><tr><th>工作</th><th>实现日期</th><th>方式</th><th>金额</th><th>确认依据</th></tr></thead><tbody>{records.flatMap(r=>(r.recoveryEntries||[]).filter(e=>(!period||e.date.startsWith(period))&&(!method||e.method===method)).map(e=><tr key={r.id+e.id}><td>{r.name}</td><td>{e.date}</td><td>{e.method}</td><td>{money(e.amount)}</td><td>{e.evidence}</td></tr>))}</tbody></table></div>
    </details></details>;
}
export function ManagerFocus({records,today,onDetail}: {records:AuditRecord[];today:string;onDetail:(r:AuditRecord)=>void}) {
  const items=records.map(r=>({r,reasons:attentionReasons(r,today)})).filter(x=>x.reasons.length).sort((a,b)=> (b.r.attention==='紧急'?2:b.r.attention==='重点'?1:0)-(a.r.attention==='紧急'?2:a.r.attention==='重点'?1:0)||a.r.dueDate.localeCompare(b.r.dueDate));
  return <details className="insight-section" open={items.length>0}><summary>经理关注 · {items.length} 项</summary><p className="muted">当前筛选范围；临近交付按7天、未更新按14天提醒。</p><div className="focus-list">{items.map(({r,reasons})=><article key={r.id}><button className="text-button" onClick={()=>onDetail(r)}>{r.name}</button><span>{r.owner} · {r.dueDate}</span><p>{reasons.join(' · ')}</p>{r.blocker&&<p>阻碍：{r.blocker}</p>}{r.supportNeeded&&<p>需要协调：{r.supportNeeded}</p>}</article>)}</div>{!items.length&&<p>当前没有需要关注的事项。</p>}</details>;
}
export function WeeklyChanges({state,onDetail}: {state:AuditState;onDetail:(r:AuditRecord)=>void}) {
  const [selected,setSelected]=useState('');
  const snap=state.snapshots.find(s=>s.id===selected)||state.snapshots.at(-1);
  const changes=snap?compareSnapshot(state.records,snap.records):null;
  const nowAmounts=recoveryStats(state.records), oldAmounts=recoveryStats(snap?.records||[]);
  const amountsComplete=nowAmounts.actualCount===nowAmounts.count && oldAmounts.actualCount===oldAmounts.count;
  const labels={added:'新增工作',completed:'转为完成',dueChanged:'交付日期调整',updated:'内容有变化',absent:'当前台账已无此项'};
  return <details className="insight-section"><summary>与周快照比较</summary>{!snap?<p>先保存一份周快照，后续即可比较变化。</p>:<>
    <label>对比基准<select aria-label="对比基准" value={snap.id} onChange={e=>setSelected(e.target.value)}>{state.snapshots.slice().reverse().map(s=><option key={s.id} value={s.id}>{s.week} · {new Date(s.savedAt).toLocaleString('zh-CN')}</option>)}</select></label>
    <p className="muted">对比当前团队全部记录与所选快照，不受列表筛选影响。不同类别可能包含同一项工作。</p>
    <div className="value-grid">{Object.entries(labels).map(([k,label])=><div key={k}><span>{label}</span><strong>{changes![k as keyof ReturnType<typeof compareSnapshot>]?.length || 0} 项</strong></div>)}</div>
    <p>挽损累计金额净变化：{amountsComplete ? money(nowAmounts.actual-oldAmounts.actual) : '部分实际金额未填写，暂不计算'}。可能包含补录、更正或删除，不代表本期到账。</p>
    {Object.entries(labels).map(([k,label])=><details key={k}><summary>{label}</summary>{changes![k as keyof ReturnType<typeof compareSnapshot>]?.map((r:AuditRecord)=><p key={r.id}><button onClick={()=>onDetail(r)}>{r.name}</button>{k==='dueChanged'&&<span> {snap.records.find(p=>p.id===r.id)?.dueDate} → {r.dueDate}</span>}{k==='absent'&&<small> 基准快照记录，仅查看</small>}</p>)}</details>)}
  </>}</details>;
}
export function OutcomeLine({record:r}: {record:AuditRecord}) {
  return <div className="outcome-line">
    {r.module==='loss-recovery' && <p>应挽损 {money(r.recoveryExpected??null)} · 实际 {money(actualAmount(r))}{r.recoveryExpected&&actualAmount(r)!==null ? ` · 比例 ${(actualAmount(r)!/r.recoveryExpected*100).toFixed(1)}%`:''}</p>}
    {r.outcomeStatus&&<span className="outcome-tag">{r.outcomeStatus}</span>}{r.outcomeCount!=null&&<span>{outcomeLabels[r.module]?.[0]||'成果'}：{r.outcomeCount}</span>}{r.outcomeSummary&&<p>{r.outcomeSummary}</p>}
  </div>;
}
