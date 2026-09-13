"use client";
import { useState, useEffect } from "react";
import Modal from "./Modal";
import CollaborationFields from "./CollaborationFields";
import RecordExtras from "./RecordExtras";
import { CONFIG, K } from "@/lib/audit/utils";
import type { AuditRecord } from "@/types/audit";
export default function RecordEditor({
  record,
  records,
  owner,
  onClose,
  onSave,
  onDelete,
  busy,
  error,
}: {
  record?: AuditRecord;
  records: AuditRecord[];
  owner: string;
  onClose: () => void;
  onSave: (record: AuditRecord) => Promise<void>;
  onDelete?: (record: AuditRecord) => Promise<void>;
  busy: boolean;
  error: string;
}) {
  const [draft, setDraft] = useState<AuditRecord>(() =>
    record
      ? K.clone(record)
      : {
          id: K.id(),
          module: "project",
          name: "",
          owner,
          progressPercent: 0,
          progress: "",
          dueDate: "",
          nextPlan: "",
          completed: false,
          updatedAt: new Date().toISOString(),
        },
  );
  const [quick, setQuick] = useState(!!record);
  const [dirty, setDirty] = useState(false);
  const [pendingEntry, setPendingEntry] = useState(false);
  const unsaved = dirty || pendingEntry;
  const [localError, setLocalError] = useState("");
  function change<T extends keyof AuditRecord>(key: T, value: AuditRecord[T]) {
    if (key === "module" && pendingEntry) {
      setLocalError("有尚未添加的挽损明细，请先添加本笔或清空本笔，再切换模块。");
      return;
    }
    setDirty(true);
    setDraft((d) => ({
      ...d,
      [key]: value,
      ...(key === "completed" && value ? { progressPercent: 100 } : {}),
    }));
  }
  function close() {
    if (!unsaved || confirm("还有未保存的修改，确认放弃并关闭？")) onClose();
  }
  useEffect(() => {
    const handler = (e: BeforeUnloadEvent) => {
      if (unsaved) {
        e.preventDefault();
        e.returnValue = "";
      }
    };
    window.addEventListener("beforeunload", handler);
    return () => window.removeEventListener("beforeunload", handler);
  }, [unsaved]);
  return (
    <Modal
      title={record ? quick ? "快速更新进展" : "完整编辑工作" : "新增工作"}
      onClose={close}
      busy={busy}
      error={localError || error}
    >
      <form
        onSubmit={async (e) => {
          e.preventDefault();
          if (pendingEntry) {
            setLocalError("有尚未添加的挽损明细，请先点击“添加本笔挽损”；如不需要，请点击“清空本笔”，再保存工作。");
            return;
          }
          const value = {
            ...draft,
            name: draft.name.trim(),
            owner: K.normalizePeople(draft.owner),
            updatedAt: new Date().toISOString(),
          };
          const errors = K.validateRecord(value);
          if (value.module === "promotion")
            errors.push("请把旧合并模块归入三促、三函或挽损后再保存");
          setLocalError(errors.join("\n"));
          if (!errors.length) await onSave(value);
        }}
      >
        <p className="muted">
          保存后写入部门台账；需要通过 Excel 交接时，可下载个人提交文件。
        </p>
        <fieldset className="editor-body" disabled={busy}>
        {record && <div className="edit-mode"><strong>{record.name}</strong><button type="button" onClick={()=>{
          if(pendingEntry){setLocalError('请先添加或清空本笔挽损，再切换编辑方式。');return;}
          setQuick(!quick);
        }}>{quick?'完整编辑':'快速更新'}</button></div>}
        {quick ? <div className="form-grid">
          <label className="full">目前进度描述<textarea aria-label="目前进度描述" maxLength={4000} value={draft.progress||''} onChange={e=>change('progress',e.target.value)}/></label>
          <label className="full">下一阶段工作内容<textarea aria-label="下一阶段工作内容" maxLength={4000} value={draft.nextPlan||''} onChange={e=>change('nextPlan',e.target.value)}/></label>
          <label>本阶段预期完成时间<input aria-label="本阶段预期完成时间" type="date" value={draft.currentStageDueDate||''} onChange={e=>change('currentStageDueDate',e.target.value)}/></label>
          <CollaborationFields draft={draft} onChange={change}/>
          <label className="full">需要协调<textarea aria-label="需要协调" maxLength={2000} value={draft.supportNeeded||''} onChange={e=>change('supportNeeded',e.target.value)}/></label>
        </div> : <>
        <div className="form-grid">
          <label>
            工作模块 *
            <select
              aria-label="工作模块"
              value={draft.module}
              onChange={(e) => change("module", e.target.value)}
            >
              {draft.module === "promotion" && (
                <option value="promotion">待归类（三促／三函／挽损）</option>
              )}
              {CONFIG.modules.map((m) => (
                <option key={m.id} value={m.id}>
                  {m.label}
                </option>
              ))}
            </select>
          </label>
          <label>
            负责人／参与人员 *
            <input
              aria-label="负责人／参与人员"
              placeholder="例如：演示甲、演示乙（多人用顿号分隔）"
              required
              maxLength={500}
              value={draft.owner}
              onChange={(e) => change("owner", e.target.value)}
            />
          </label>
          <label className="full">
            工作名称 *
            <input
              aria-label="工作名称"
              required
              maxLength={200}
              placeholder="例如：家财险承保资料完整性专项"
              value={draft.name}
              onChange={(e) => change("name", e.target.value)}
            />
          </label>
          <label>
            整体进度（%）
            <input
              aria-label="项目进度"
              type="number"
              min={0}
              max={100}
              step={1}
              disabled={draft.completed}
              value={draft.progressPercent ?? ""}
              onChange={(e) =>
                change(
                  "progressPercent",
                  e.target.value === "" ? null : Number(e.target.value),
                )
              }
            />
            <span className="presets">
              {[0, 25, 50, 75, 100].map((n) => (
                <button
                  key={n}
                  type="button"
                  disabled={draft.completed}
                  onClick={() => change("progressPercent", n)}
                >
                  {n}%
                </button>
              ))}
            </span>
          </label>
          <label>
            项目整体交付日期 *
            <input
              aria-label="项目整体交付日期"
              required
              type="date"
              min="1900-01-01"
              max="9999-12-31"
              value={draft.dueDate}
              onChange={(e) => change("dueDate", e.target.value)}
            />
          </label>
          <fieldset className="full stage-form">
            <legend>上一阶段 · 已完成</legend>
            <label>
              已完成阶段内容
              <textarea
                aria-label="已完成阶段内容"
                maxLength={4000}
                placeholder="新启动的工作可留空"
                value={draft.previousStageContent ?? ""}
                onChange={(e) => change("previousStageContent", e.target.value)}
              />
            </label>
            <label>
              已完成阶段完成日期
              <input
                aria-label="已完成阶段完成日期"
                type="date"
                min="1900-01-01"
                max="9999-12-31"
                value={draft.previousStageCompletedDate ?? ""}
                onChange={(e) =>
                  change("previousStageCompletedDate", e.target.value)
                }
              />
            </label>
          </fieldset>
          <fieldset className="full stage-form">
            <legend>本阶段 · 正在推进</legend>
            <label>
              本阶段项目任务
              <textarea
                aria-label="本阶段项目任务"
                maxLength={4000}
                placeholder="例如：核查赔付依据及审批流程"
                value={draft.currentStageTask ?? ""}
                onChange={(e) => change("currentStageTask", e.target.value)}
              />
            </label>
            <label>
              目前进度描述
              <textarea
                aria-label="目前进度描述"
                maxLength={4000}
                placeholder="例如：已核查30笔，剩余20笔待补充资料"
                value={draft.progress ?? ""}
                onChange={(e) => change("progress", e.target.value)}
              />
            </label>
            <label>
              本阶段预期完成时间
              <input
                aria-label="本阶段预期完成时间"
                type="date"
                min="1900-01-01"
                max="9999-12-31"
                value={draft.currentStageDueDate ?? ""}
                onChange={(e) => change("currentStageDueDate", e.target.value)}
              />
            </label>
            <p className="muted">
              本阶段到期仅作阶段提醒；整体状态根据项目整体交付日期计算。日期未知可暂留空。
            </p>
          </fieldset>
          <fieldset className="full stage-form">
            <legend>下一阶段 · 后续安排</legend>
            <label>
              下一阶段工作内容
              <textarea
                aria-label="下一阶段工作内容"
                maxLength={4000}
                placeholder="例如：汇总问题清单并与业务部门核实；最后阶段可留空"
                value={draft.nextPlan ?? ""}
                onChange={(e) => change("nextPlan", e.target.value)}
              />
            </label>
          </fieldset>
          <label className="full check">
            <input
              aria-label="整项已完成"
              type="checkbox"
              checked={draft.completed}
              onChange={(e) => change("completed", e.target.checked)}
            />
            整项工作已完成
          </label>
        </div>
        <p className="muted">
          填写 100%
          不自动确认完成。取消完成标记后，请重新核对整体百分比和阶段安排。
        </p>
        <RecordExtras pendingEntry={pendingEntry} onPendingEntryChange={value=>{setPendingEntry(value);setLocalError("");}} draft={draft} records={records} busy={busy} setDraft={r=>{setDirty(true);setDraft(r);}}/>
        <details>
          <summary>记录信息</summary>
          <p className="metadata">
            编号：{draft.id}
            <br />
            更新时间：{draft.updatedAt}
          </p>
        </details>
        </>}
        </fieldset>
        <div className="actions">
          {record && !quick && onDelete && (
            <button
              type="button"
              className="danger"
              disabled={busy}
              onClick={() => {
                if (confirm(`确认删除“${record.name}”？已有周报保持不变。`))
                  void onDelete(record);
              }}
            >
              删除这项工作
            </button>
          )}
          <button type="button" onClick={close} disabled={busy}>
            取消
          </button>
          <button className="primary" disabled={busy} type="submit">
            {busy ? "正在保存…" : "保存工作"}
          </button>
        </div>
      </form>
    </Modal>
  );
}
