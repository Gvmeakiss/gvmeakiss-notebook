"use client";
import { StageHistory } from "./RecordExtras";
import { OutcomeLine, money } from "./Insights";
import Modal from "./Modal";
import { CONFIG, K } from "@/lib/audit/utils";
import type { AuditRecord } from "@/types/audit";
export default function AuditDetail({
  record: r,
  records,
  frozen,
  legacy,
  asOfDate,
  onClose,
  onEdit,
  onRelated,
}: {
  record: AuditRecord;
  records: AuditRecord[];
  frozen: boolean;
  legacy: boolean;
  asOfDate?: string;
  onClose: () => void;
  onEdit?: () => void;
  onRelated?: (record: AuditRecord) => void;
}) {
  const status = frozen ? r.frozenStatus! : K.status(r, asOfDate);
  const pct = K.percent(r);
  return (
    <Modal title={r.name} onClose={onClose}>
      <p>
        {r.owner} ·{" "}
        {legacy && r.module === "project"
          ? "项目"
          : legacy && r.module === "promotion"
            ? "三促／三函／挽损"
            : K.moduleName(r.module)}{" "}
        ·{" "}
        <span className={`badge ${status}`}>
          {CONFIG.statuses[status].label}
        </span>{status==='overdue' && <small className="overdue-rule">未完成，且整体交付日期早于{frozen?`留档基准日 ${asOfDate}`:"今天"}；当天到期不算逾期</small>}
      </p>
      <div className="detail-summary">
        <div>
          <span className="muted">整体进度</span>
          <strong>{pct === null ? "未填写" : `${pct}%`}</strong>
          {pct !== null && (
            <progress aria-label="整体进度" value={pct} max={100} />
          )}
        </div>
        <div>
          <span className="muted">
            {legacy ? "预计交付日期" : "项目整体交付日期"}
          </span>
          <strong>{r.dueDate}</strong>
        </div>
      </div>
      {frozen && (
        <p className="notice">
          历史留档 · 状态基准日 {asOfDate}。
          {legacy
            ? "这是旧版记录，按原字段展示，未补造阶段内容。"
            : "内容及阶段提醒均按留档日展示。"}
        </p>
      )}
      {legacy ? (
        <dl>
          <dt>现阶段进展</dt>
          <dd>{r.progress || "—"}</dd>
          <dt>下一步计划</dt>
          <dd>{r.nextPlan || "—"}</dd>
        </dl>
      ) : (
        <div className="stage-timeline" aria-label="三个阶段">
          <section className="stage-row">
            <h3>
              上一阶段<small>已完成</small>
            </h3>
            <div>
              <h4>已完成阶段内容</h4>
              <p>{r.previousStageContent || "暂无已完成阶段内容"}</p>
            </div>
            <div>
              <h4>已完成阶段完成日期</h4>
              <p>{r.previousStageCompletedDate || "未填写"}</p>
            </div>
          </section>
          <section className="stage-row current">
            <h3>
              本阶段<small>当前任务</small>
            </h3>
            <div>
              <h4>本阶段项目任务</h4>
              <p>{r.currentStageTask || "暂未填写"}</p>
              <h4>目前进度描述</h4>
              <p>{r.progress || "暂未填写"}</p>
            </div>
            <div>
              <h4>本阶段预期完成时间</h4>
              <p>{r.currentStageDueDate || "未填写"}</p>
              {K.stageOverdue(r, asOfDate) && (
                <span className="badge overdue">本阶段已超期</span>
              )}
            </div>
          </section>
          <section className="stage-row">
            <h3>
              下一阶段<small>后续安排</small>
            </h3>
            <div>
              <h4>下一阶段工作内容</h4>
              <p>{r.nextPlan || "暂无后续阶段安排"}</p>
            </div>
            <div>
              <h4>说明</h4>
              <p className="muted">整体交付日期见上方</p>
            </div>
          </section>
        </div>
      )}
      <StageHistory record={r}/>
      {r.archivedAt && <p className="notice">已归档 · {new Date(r.archivedAt).toLocaleString('zh-CN')}。如需修改，请从归档栏恢复到工作清单。</p>}
      <section className="action-card"><h3>工作成果</h3><OutcomeLine record={r}/>
        <p>成果覆盖范围：{r.coverage || '—'}</p><p>事项确认依据：{r.evidence || (r.recoveryEntries?.length ? '分笔依据见下方明细' : '待确认')}{r.confirmedDate ? ' · '+r.confirmedDate : ''}</p>
        {r.module==='three-letters'&&<p>发函 {r.letterSentDate || '—'} · 回复期限 {r.replyDueDate || '—'} · 实际回复 {r.replyDate || '—'}</p>}
        {(r.relatedRecordIds||'').split(',').filter(Boolean).map(id=>{const source=records.find(x=>x.id===id);return <details key={id}><summary>关联：{source?.name || id}</summary><p>{source?.outcomeSummary || '此编号的来源工作未提供成果摘要，或已不在当前范围。'}</p>{source&&onRelated&&<button onClick={()=>onRelated(source)}>查看关联工作详情</button>}</details>;})}
        {r.recoveryKey&&<p>挽损成果编号：{r.recoveryKey}</p>}
        {r.recoveryEntries?.map(e=><p key={e.id}>{e.date} · {e.method} · {money(e.amount)} · {e.evidence}</p>)}
      </section>
      {(r.attention || r.blocker || r.supportNeeded) && <section className="action-card"><h3>关注与协调 · {r.attention || '普通'}</h3><p>阻碍：{r.blocker || '无'}</p><p>需要协调：{r.supportNeeded || '无'}</p></section>}
      {(r.collaborationStatus || r.followUpDate) && <p className="muted">协作状态：{r.collaborationStatus||'未填写'} · 跟进日期：{r.followUpDate||'未填写'}</p>}
      <p className="record-remark">备注：{r.remarks||'—'}</p>
      {r.tracking && (
        <details>
          <summary>历史工作跟踪</summary>
          <p>{r.tracking}</p>
        </details>
      )}
      <details>
        <summary>记录信息</summary>
        <p className="metadata">
          编号：{r.id}
          <br />
          更新时间：{r.updatedAt}
        </p>
      </details>
      <div className="actions">
        <button onClick={onClose}>关闭</button>
        {onEdit && (
          <button className="primary" onClick={onEdit}>
            更新进展
          </button>
        )}
      </div>
    </Modal>
  );
}
