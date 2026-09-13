"use client";
import CollaborationFields from "./CollaborationFields";
import { useState } from 'react';
import type { AuditRecord, RecoveryEntry } from '@/types/audit';
import { K } from '@/lib/domain/core';
import { actualAmount, outcomeLabels, advanceStage } from '@/lib/domain/enhancements.js';
export function StageHistory({record}: {record:AuditRecord}) {
  return <details className="history-log"><summary>历次阶段记录（{record.stageHistory?.length || 0}）</summary>
    <p className="muted">保留修改或阶段推进前的内容。旧数据只显示已有内容，无法补造此前被覆盖的信息。</p>
    {record.stageHistory?.slice().reverse().map(h => <article key={h.id}><h4>{h.reason} · {new Date(h.recordedAt).toLocaleString('zh-CN')}</h4><dl>
      <dt>当时的上一阶段</dt><dd>{h.previousStageContent || '—'} {h.previousStageCompletedDate}</dd>
      <dt>当时的本阶段</dt><dd>{h.currentStageTask || '—'}</dd><dt>当时的进展</dt><dd>{h.progress || '—'}</dd>
      <dt>阶段预期完成时间</dt><dd>{h.currentStageDueDate || '—'}</dd><dt>当时的下一阶段</dt><dd>{h.nextPlan || '—'}</dd>
    </dl></article>)}
  </details>;
}
export default function RecordExtras({draft,setDraft,records,busy,pendingEntry,onPendingEntryChange}: {draft:AuditRecord;setDraft:(r:AuditRecord)=>void;records:AuditRecord[];busy:boolean;pendingEntry:boolean;onPendingEntryChange:(pending:boolean)=>void}) {
  const [date,setDate] = useState(K.localDate()), [notice,setNotice] = useState('');
  const [entry,setEntry] = useState({date:K.localDate(),amount:'',method:'资金追回',evidence:'',note:''});
  const changeEntry = (next:typeof entry) => {setEntry(next);onPendingEntryChange(true);};
  const change = (key:keyof AuditRecord, value:unknown) => setDraft({...draft,[key]:value});
  const text = (key:keyof AuditRecord,label:string, type='text') => <label>{label}<input aria-label={label} type={type} maxLength={type==='text'?500:undefined} value={String(draft[key]??'')} onChange={e=>change(key,e.target.value)}/></label>;
  const area = (key:keyof AuditRecord,label:string) => <label className="full">{label}<textarea aria-label={label} maxLength={2000} value={String(draft[key]??'')} onChange={e=>change(key,e.target.value)}/></label>;
  const number = (key:keyof AuditRecord,label:string,disabled=false) => <label>{label}<input aria-label={label} type="number" min="0" max="100000000000" step="0.01" disabled={disabled} value={draft[key] as number ?? ''} onChange={e=>change(key,e.target.value===''?null:Number(e.target.value))}/></label>;
  const entries = draft.recoveryEntries || [];
  const actual = actualAmount(draft);
  return <>
    <fieldset className="stage-form"><legend>长期阶段跟踪</legend><p>完成本阶段后，先留存当前三阶段内容，再将下一阶段带入本阶段。保存工作后生效。</p>
      <label>本阶段实际完成日期<input aria-label="本阶段实际完成日期" type="date" value={date} onChange={e=>setDate(e.target.value)}/></label>
      <button type="button" disabled={busy || draft.completed} onClick={()=> {try {if (!K.validDate(date) || date>K.localDate()) throw new Error('请填写不晚于今天的有效完成日期');setDraft(advanceStage(draft,date,K.id));setNotice('已归档并推进，请填写新阶段内容后保存工作');}catch(e){setNotice(e instanceof Error?e.message:'推进失败');}}}>完成本阶段并推进</button>
      {notice && <p role="status" className="notice">{notice}</p>}<StageHistory record={draft}/>
    </fieldset>
    <fieldset className="stage-form"><legend>关注与协调</legend><div className="form-grid">
      <label>关注级别<select aria-label="关注级别" value={draft.attention||'普通'} onChange={e=>change('attention',e.target.value)}>{['普通','重点','紧急'].map(v=><option key={v}>{v}</option>)}</select></label>
      <CollaborationFields draft={draft} onChange={change}/>
      {area('remarks','备注')}
      {area('blocker','当前阻碍')}{area('supportNeeded','需要协调')}
    </div></fieldset>
    <fieldset className="stage-form"><legend>模块成果</legend><div className="form-grid">
      <label>成果状态<select aria-label="成果状态" value={draft.outcomeStatus||''} onChange={e=>change('outcomeStatus',e.target.value)}><option value="">未填写</option>{['待确认','已确认','研究中','形成方案','被采纳','已应用','推进中','已落实','待回复','已回复'].map(v=><option key={v}>{v}</option>)}</select></label>
      <label>{outcomeLabels[draft.module]?.[0] || '成果数量'}<input aria-label="成果数量" type="number" min="0" max="1000000" step="1" value={draft.outcomeCount??''} onChange={e=>change('outcomeCount',e.target.value===''?null:Number(e.target.value))}/></label>
      {area('outcomeSummary',outcomeLabels[draft.module]?.[1] || '成果摘要')}{text('coverage','成果覆盖范围')}
      {draft.module==='three-letters' && <>{text('letterSentDate','发函日期','date')}{text('replyDueDate','回复期限','date')}{text('replyDate','实际回复日期','date')}</>}
      {area('evidence','成果确认依据')}{text('confirmedDate','成果确认日期','date')}
      <label className="full">关联来源工作<select aria-label="关联来源工作" multiple value={(draft.relatedRecordIds||'').split(',').filter(Boolean)} onChange={e=>change('relatedRecordIds',Array.from(e.target.selectedOptions,o=>o.value).join(','))}>{Array.from(new Map([...records.filter(r=>r.id!==draft.id),...(draft.relatedRecordIds||'').split(',').filter(id=>id && !records.some(r=>r.id===id)).map(id=>({id,name:'已不在当前台账 · '+id}))].map(r=>[r.id,r])).values()).map(r=><option key={r.id} value={r.id}>{r.name}</option>)}</select><small>同一成果在一个模块登记，其他工作通过关联引用。按住 Command/Ctrl 可多选或取消。</small></label>
    </div></fieldset>
    {draft.module === 'loss-recovery' && <fieldset className="stage-form"><legend>挽损贡献 · 金额单位：元</legend><div className="form-grid">
      {number('recoveryExpected','应挽损金额（元）')}{number('recoveryActual','累计实际挽损（元）',entries.length>0)}
      {text('recoveryKey','挽损成果编号')}
      <label>累计挽损实现方式<select aria-label="累计挽损实现方式" value={draft.recoveryMethod||''} disabled={entries.length>0} onChange={e=>change('recoveryMethod',e.target.value)}><option value="">请选择</option>{['资金追回','核减支付','其他已确认实现'].map(v=><option key={v}>{v}</option>)}</select></label>
    </div><p>挽损比例：{draft.recoveryExpected && actual!==null ? (actual/draft.recoveryExpected*100).toFixed(1)+'%' : '—'}；尚未实现：{draft.recoveryExpected!=null && actual!==null ? (draft.recoveryExpected-actual).toFixed(2)+' 元':'待确认'}</p>
      {actual!==null && draft.recoveryExpected!=null && actual>draft.recoveryExpected && <p className="notice">实际金额超过应挽损金额，请核对应挽损口径。</p>}
      <p className="muted">累计值模式需要上方确认依据及日期。明细模式按每笔实际实现日期统计，未确认的预计损失不计入实际。</p>
      <details open={entries.length>0 || pendingEntry}><summary>分批挽损明细（{entries.length} 笔）</summary>
        {entries.map(row=><article key={row.id} className="recovery-entry"><strong>{row.date} · {row.method} · {row.amount.toFixed(2)} 元</strong><p>{row.evidence}{row.note ? '；'+row.note:''}</p><button type="button" onClick={()=> {const remaining=entries.filter(e=>e.id!==row.id);setDraft({...draft,recoveryEntries:remaining,recoveryActual:remaining.length?Math.round(remaining.reduce((s,e)=>s+Math.round(e.amount*100),0))/100:null});}}>移除此笔</button></article>)}
        {!entries.length && (draft.recoveryActual||0)>0 && <p className="notice">已有累计金额。首次使用明细时，请把历史实际金额按可核实的日期拆成明细；明细合计会替代累计值，不重复相加。</p>}
        <fieldset disabled={busy}><legend>填写本笔</legend><div className="form-grid">
          <label>本笔实现日期<input aria-label="本笔实现日期" type="date" value={entry.date} onChange={e=>changeEntry({...entry,date:e.target.value})}/></label>
          <label>本笔金额（元）<input aria-label="本笔金额（元）" type="number" min="0.01" step="0.01" value={entry.amount} onChange={e=>changeEntry({...entry,amount:e.target.value})}/></label>
          <label>本笔实现方式<select aria-label="本笔实现方式" value={entry.method} onChange={e=>changeEntry({...entry,method:e.target.value})}>{['资金追回','核减支付','其他已确认实现'].map(v=><option key={v}>{v}</option>)}</select></label>
          <label>本笔确认依据<input aria-label="本笔确认依据" value={entry.evidence} maxLength={2000} onChange={e=>changeEntry({...entry,evidence:e.target.value})}/></label>
          <label>本笔备注<input aria-label="本笔备注" value={entry.note} maxLength={2000} onChange={e=>changeEntry({...entry,note:e.target.value})}/></label>
        </div><button type="button" onClick={()=>{
          const row:RecoveryEntry={...entry,amount:Number(entry.amount),id:K.id()};
          const nextEntries=[...entries,row];const next={...draft,recoveryEntries:nextEntries,recoveryActual:nextEntries.reduce((s,e)=>s+Math.round(e.amount*100),0)/100};
          const errors=K.validateRecord(next).filter(e=>e.includes('明细'));
          if (errors.length) {setNotice(errors.join('；'));return;}
          setDraft(next);setEntry({...entry,amount:'',evidence:'',note:''});onPendingEntryChange(false);setNotice('已添加明细，请保存工作');
        }}>添加本笔挽损</button>
        <button type="button" disabled={!pendingEntry} onClick={()=>{
          if (!confirm('确认清空尚未添加的本笔挽损？已添加的明细保持不变。')) return;
          setEntry({date:K.localDate(),amount:'',method:'资金追回',evidence:'',note:''});onPendingEntryChange(false);setNotice('已清空本笔');
        }}>清空本笔</button>
        {pendingEntry && <p className="notice" role="status">本笔尚未添加，请添加本笔或清空本笔后再保存工作。</p>}
        </fieldset>
      </details>
    </fieldset>}
  </>;
}
