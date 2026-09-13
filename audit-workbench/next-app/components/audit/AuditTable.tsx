"use client";
import { Fragment } from "react";
import RecordNote from "./RecordNote";
import type { ReactNode } from "react";
import type { AuditRecord } from "@/types/audit";
import { K } from "@/lib/audit/utils";
export default function AuditTable({
  records,
  layout,
  frozen,
  disabled,
  legacy,
  asOfDate,
  progress,
  badge,
  onDetail,
  onEdit,
  onArchive,
  noteDrafts,
  onNoteChange,
  onNoteSave,
  onNoteCancel,
}: {
  noteDrafts: Record<string,string>;
  onNoteChange:(r:AuditRecord,value:string)=>void;
  onNoteSave:(r:AuditRecord)=>void;
  onNoteCancel:(id:string)=>void;
  records: AuditRecord[];
  layout: "list" | "cards";
  frozen: boolean;
  disabled: boolean;
  legacy: boolean;
  asOfDate?: string;
  progress: (r: AuditRecord) => ReactNode;
  badge: (r: AuditRecord) => ReactNode;
  onDetail: (r: AuditRecord) => void;
  onEdit: (r: AuditRecord) => void;
  onArchive: (r: AuditRecord) => void;
}) {
  const note = (r:AuditRecord) => <RecordNote record={r} draft={noteDrafts[r.id]} readOnly={frozen||!!r.archivedAt} disabled={disabled} onChange={value=>onNoteChange(r,value)} onSave={()=>onNoteSave(r)} onCancel={()=>onNoteCancel(r.id)}/>;
  const collaboration = (r:AuditRecord) => (r.collaborationStatus||r.followUpDate)?<small className="collaboration-line">{r.collaborationStatus||'协作状态未填写'}{r.followUpDate?` · 跟进 ${r.followUpDate}`:''}</small>:null;
  const actions = (r: AuditRecord) => <div className="record-actions">
    <button disabled={disabled && !frozen} onClick={()=>frozen || r.archivedAt ? onDetail(r) : onEdit(r)}>
      {frozen ? '查看阶段' : r.archivedAt ? '查看详情' : '更新进展'}
    </button>
    {!frozen && <button className={r.archivedAt ? 'archive-restore' : 'archive-button'}
      aria-label={`${r.archivedAt ? '恢复到工作清单' : '归档'} ${r.name}`}
      title={r.archivedAt ? '恢复后保留已完成状态，可再更新进展' : r.completed ? '归档后移出日常清单，历史和成果继续保留' : '请先在更新进展中确认整项工作已完成'}
      disabled={disabled || noteDrafts[r.id]!==undefined || (!r.archivedAt && !r.completed)} onClick={()=>onArchive(r)}>
      {r.archivedAt ? '恢复到工作清单' : '归档'}
    </button>}
  </div>;
  return (
    <>
      {" "}
      {layout === "list" ? (
        <div className="table-wrap">
          <table className="work-table" data-legacy={legacy}>
            <thead>
              <tr>
                <th>工作事项 / 参与人员</th>
                <th>整体进度</th>
                <th>整体交付 / 状态</th>
                <th>{legacy ? "现阶段进展" : "本阶段项目任务"}</th>
                <th>{legacy ? "下一步计划" : "目前进度描述"}</th>
                <th>操作</th>
              </tr>
            </thead>
            <tbody>
              {records.map((r) => (
                <Fragment key={r.id}><tr data-testid="work-row">
                  <td>
                    <button
                      className="record-name"
                      onClick={() => {
                        onDetail(r);
                      }}
                    >
                      {r.name}
                    </button>
                    <span className="row-owner">{r.owner}</span>{collaboration(r)}
                    {r.archivedAt && <small className="archive-date">归档于 {new Date(r.archivedAt).toLocaleDateString("zh-CN")}</small>}
                  </td>
                  <td>{progress(r)}</td>
                  <td>
                    {r.dueDate}
                    <br />
                    {badge(r)}
                    {K.stageOverdue(r, asOfDate) && (
                      <span><span className="badge overdue">本阶段已超期</span><small className="overdue-rule">未完成，且本阶段预期完成时间早于{frozen?`留档基准日 ${asOfDate}`:"今天"}</small></span>
                    )}
                  </td>
                  <td className="row-text">
                    <p title={legacy ? r.progress : r.currentStageTask}>
                      {(legacy ? r.progress : r.currentStageTask) || "暂未填写"}
                    </p>
                  </td>
                  <td className="row-text">
                    <p title={legacy ? r.nextPlan : r.progress}>
                      {(legacy ? r.nextPlan : r.progress) || "—"}
                    </p>
                  </td>
                  <td>
                    {actions(r)}
                  </td>
                </tr><tr className="note-row"><td colSpan={6}>{note(r)}</td></tr></Fragment>
              ))}
            </tbody>
          </table>
        </div>
      ) : (
        <div className="cards">
          {records.map((r) => (
            <article key={r.id} data-testid="work-row">
              <div className="card-top">
                {badge(r)}
                <span>{r.owner}</span>
              </div>
              <button
                className="record-name"
                onClick={() => {
                  onDetail(r);
                }}
              >
                {r.name}
              </button>
              {progress(r)}
              <p className="muted">整体交付 {r.dueDate}</p>
              {r.archivedAt && <p className="archive-date">归档于 {new Date(r.archivedAt).toLocaleDateString("zh-CN")}</p>}
              <h4>{legacy ? "现阶段进展" : "本阶段项目任务"}</h4>
              <p>{(legacy ? r.progress : r.currentStageTask) || "暂未填写"}</p>
              <h4>{legacy ? "下一步计划" : "目前进度描述"}</h4>
              <p>{(legacy ? r.nextPlan : r.progress) || "—"}</p>
              {K.stageOverdue(r, asOfDate) && (
                <p><span className="badge overdue">本阶段已超期</span><small className="overdue-rule">未完成，且本阶段预期完成时间 {r.currentStageDueDate} 早于{frozen?`留档基准日 ${asOfDate}`:"今天"}</small></p>
              )}
              {collaboration(r)}
              {actions(r)}
              {note(r)}
            </article>
          ))}
        </div>
      )}
    </>
  );
}
