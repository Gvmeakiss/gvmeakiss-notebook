"use client";
import { useState, useRef } from "react";
import Modal from "./Modal";
import { CONFIG, K } from "@/lib/audit/utils";
import { excelAdapter, exportExcel } from "@/lib/audit/excel";
import type { AuditRecord, MergeItem } from "@/types/audit";
export default function ImportDialog({
  current,
  teamId,
  onClose,
  onApply,
  busy,
  error,
}: {
  current: AuditRecord[];
  teamId: string;
  onClose: () => void;
  onApply: (
    plan: MergeItem[],
    choices: Record<string, string>,
  ) => Promise<void>;
  busy: boolean;
  error: string;
}) {
  const [plan, setPlan] = useState<MergeItem[]>([]),
    [choices, setChoices] = useState<Record<string, string>>({}),
    [localError, setError] = useState(""),
    [reading, setReading] = useState(false),
    [ack, setAck] = useState(false);
  const [unbound,setUnbound] = useState(false), [bindAck,setBindAck] = useState(false);
  const sequence = useRef(0);
  const counts = {
    new: plan.filter((p) => p.kind === "new").length,
    same: plan.filter((p) => p.kind === "same").length,
    conflict: plan.filter((p) => p.kind === "conflict").length,
  };
  const fields = [
    { key: "module", label: "模块" },
    ...CONFIG.fields.filter(
      (f) =>
        !f.legacy ||
        plan.some((p) => p.record.tracking || p.existing?.tracking),
    ),
    { key: "updatedAt", label: "更新时间" },
  ];
  function value(r: AuditRecord, key: string): string {
    if (key === "module") return K.moduleName(r.module);
    const v = r[key as keyof AuditRecord];
    if (key === 'recoveryEntries') return r.recoveryEntries?.map(e=>`${e.date} · ${e.method} · ${e.amount.toFixed(2)} 元 · ${e.evidence}${e.note?' · '+e.note:''}`).join('\n') || '无明细';
    if (key === 'stageHistory') return r.stageHistory?.map(h=>`${new Date(h.recordedAt).toLocaleString('zh-CN')} · ${h.reason}\n上一阶段：${h.previousStageContent||'—'}\n本阶段：${h.currentStageTask||'—'}\n进展：${h.progress||'—'}\n下一阶段：${h.nextPlan||'—'}`).join('\n\n') || '无历史';
    return typeof v === "boolean" ? (v ? "是" : "否") : String(v ?? "");
  }
  async function read(file?: File) {
    const id = ++sequence.current;
    setPlan([]);
    setChoices({});
    setAck(false);
    setUnbound(false);setBindAck(false);
    setError("");
    if (!file) return;
    setReading(true);
    try {
      if (file.size > CONFIG.limits.maxFileBytes)
        throw new Error("文件超过15MB，请拆分记录");
      if (!/\.(xlsx|json)$/i.test(file.name))
        throw new Error("请选择 .xlsx 或 .json 文件");
      let records: AuditRecord[];
      if (/\.json$/i.test(file.name)) {
        const data = JSON.parse(await file.text());
        if (data.teamId && data.teamId !== teamId) throw new Error("文件属于其他团队，请切换团队");
        records = K.recordsFromImport(data).map(r=>({...r,...(data.teamId?{teamId:data.teamId}:{})}));
      } else records = (await excelAdapter()).read(await file.arrayBuffer(), {teamId});
      if (records.some(r=>r.teamId && r.teamId!==teamId)) throw new Error("文件包含其他团队记录，不能合并");
      setUnbound(records.some(r=>!r.teamId));
      records = records.map(r=>({...r,teamId}));
      const preview = K.prepareMerge(current, records);
      if (id === sequence.current) {
        setPlan(preview);
        if (!preview.length) setError("文件中没有记录");
      }
    } catch (e) {
      if (id === sequence.current)
        setError(e instanceof Error ? e.message : "文件无法读取");
    } finally {
      if (id === sequence.current) setReading(false);
    }
  }
  return (
    <Modal
      title="汇总同事进展"
      onClose={() => {
        sequence.current++;
        onClose();
      }}
      busy={busy}
      error={localError || error}
    >
      <p className="muted">分批挽损填写“挽损明细”工作表；有明细的记录按明细合计计算实际金额，主表累计值不重复相加。</p>
      <p>
        预览后再合并。新编号新增，相同内容跳过；不同内容逐条选择，未选择的冲突保留当前版。
      </p>
      <div className="actions">
        <button
          onClick={() =>
            void exportExcel([], "稽核填写模板", false, false, teamId).catch((e) =>
              setError(e.message),
            )
          }
        >
          下载填写模板
        </button>
        <label className="file-label">
          选择提交文件
          <input
            aria-label="选择提交文件"
            type="file"
            accept=".xlsx,.json"
            disabled={busy}
            onChange={(e) => void read(e.target.files?.[0])}
          />
        </label>
      </div>
      {reading ? (
        <p role="status">读取与校验中…</p>
      ) : (
        <p className="notice" data-testid="import-summary">
          新增 {counts.new} 项 · 相同跳过 {counts.same} 项 · 待选择{" "}
          {counts.conflict} 项
        </p>
      )}
      {unbound && <label className="notice"><input type="checkbox" aria-label="确认旧文件所属团队" checked={bindAck} onChange={e=>setBindAck(e.target.checked)}/>此旧文件没有团队信息，确认其中记录属于当前团队后再合并。</label>}
      <div className="import-list">
        {plan
          .filter((p) => p.kind !== "same")
          .map((item) => (
            <article className="merge-item" key={item.record.id}>
              <h3>
                {item.kind === "new" ? "新增" : "内容有变化"} ·{" "}
                {item.record.name}
              </h3>
              <p className="muted">
                {item.record.owner} · {K.moduleName(item.record.module)}
              </p>
              {item.warning && <p className="notice">{item.warning}</p>}
              <div className="table-wrap">
                <table>
                  <thead>
                    <tr>
                      <th>字段</th>
                      {item.existing && <th>当前内容</th>}
                      <th>导入内容</th>
                    </tr>
                  </thead>
                  <tbody>
                    {fields
                      .filter(
                        (f) =>
                          !item.existing ||
                          value(item.existing, f.key) !==
                            value(item.record, f.key),
                      )
                      .map((f) => (
                        <tr key={f.key}>
                          <td>{f.label}</td>
                          {item.existing && (
                            <td>{value(item.existing, f.key)}</td>
                          )}
                          <td>{value(item.record, f.key)}</td>
                        </tr>
                      ))}
                  </tbody>
                </table>
              </div>
              <details>
                <summary>展开完整导入内容与编号</summary>
                <dl>
                  {fields.map((f) => (
                    <div key={f.key}>
                      <dt>{f.label}</dt>
                      <dd>{value(item.record, f.key)}</dd>
                    </div>
                  ))}
                  <div>
                    <dt>编号</dt>
                    <dd>{item.record.id}</dd>
                  </div>
                </dl>
              </details>
              {item.kind === "conflict" && (
                <label>
                  采用的版本
                  <select
                    aria-label={`版本选择 ${item.record.id}`}
                    value={choices[item.record.id] || "current"}
                    onChange={(e) =>
                      setChoices({
                        ...choices,
                        [item.record.id]: e.target.value,
                      })
                    }
                  >
                    <option value="current">保留已有内容（默认）</option>
                    <option value="incoming">采用同事提交的内容</option>
                  </select>
                </label>
              )}
            </article>
          ))}
      </div>
      {counts.same > 0 && (
        <details>
          <summary>{counts.same} 项内容相同，无需修改</summary>
          <ul>
            {plan
              .filter((p) => p.kind === "same")
              .map((p) => (
                <li key={p.record.id}>
                  {p.record.name}
                  {p.warning && ` · ${p.warning}`}
                </li>
              ))}
          </ul>
        </details>
      )}
      {plan.some((p) => p.warning) && (
        <label className="check">
          <input
            type="checkbox"
            checked={ack}
            onChange={(e) => setAck(e.target.checked)}
          />
          已核对同名工作，确认是不同事项
        </label>
      )}
      <div className="actions">
        <button disabled={busy} onClick={onClose}>
          取消
        </button>
        <button
          className="primary"
          disabled={
            busy ||
            reading ||
            !plan.length ||
            !!localError ||
            (unbound && !bindAck) ||
            (plan.some((p) => p.warning) && !ack)
          }
          onClick={() => void (unbound && !bindAck ? Promise.resolve() : onApply(plan, choices))}
        >
          确认汇总
        </button>
      </div>
    </Modal>
  );
}
