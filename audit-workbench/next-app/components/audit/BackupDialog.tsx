"use client";
import { useState } from "react";
import Modal from "./Modal";
import { bindTeam } from "@/lib/audit/api";
import { K, CONFIG } from "@/lib/audit/utils";
import { download } from "@/lib/audit/excel";
import type { AuditState } from "@/types/audit";
export function backupText(state: AuditState) {
  return JSON.stringify(
    { ...state, exportedAt: new Date().toISOString() },
    null,
    2,
  );
}
export default function BackupDialog({
  current,
  onClose,
  onRestore,
  busy,
  error,
}: {
  current: AuditState;
  onClose: () => void;
  onRestore: (state: AuditState) => Promise<void>;
  busy: boolean;
  error: string;
}) {
  const [candidate, setCandidate] = useState<AuditState | null>(null),
    [expected, setExpected] = useState(""),
    [verified, setVerified] = useState(false),
    [localError, setError] = useState(""),
    [reading, setReading] = useState(false);
  return (
    <Modal
      title="备份与恢复"
      onClose={onClose}
      busy={busy || reading}
      error={localError || error}
    >
      <section className="action-card">
        <h3>全部工作备份</h3>
        <p>
          包含当前台账与所有历史周报。下载后确认文件已保存；备份不会自动上传到其他地方。
        </p>
        <button
          className="primary"
          onClick={() =>
            download(backupText(current), `稽核完整备份_${Date.now()}.json`)
          }
        >
          下载全部工作备份
        </button>
      </section>
      <section className="action-card">
        <h3>从完整备份恢复</h3>
        <p>会替换当前部门的全部工作和历史周报。日常提交请用“汇总同事进展”。</p>
        <label>
          1. 选择要恢复的备份
          <input
            aria-label="选择恢复备份"
            disabled={busy || reading}
            type="file"
            accept=".json"
            onChange={async (e) => {
              setCandidate(null);
              setExpected("");
              setVerified(false);
              setError("");
              const f = e.target.files?.[0];
              if (!f) return;
              setReading(true);
              try {
                if (f.size > CONFIG.limits.maxFileBytes)
                  throw new Error("文件超过15MB");
                const loaded = K.validateBackup(JSON.parse(await f.text()));
                setCandidate(bindTeam(loaded, current.teamId || "default"));
              } catch (e) {
                setError(e instanceof Error ? e.message : "文件无效");
              } finally {
                setReading(false);
              }
            }}
          />
        </label>
        {candidate && (
          <p className="notice">
            备份有 {candidate.records.length} 项、{candidate.snapshots.length}{" "}
            份周报；将替换当前 {current.records.length} 项、
            {current.snapshots.length} 份周报。
          </p>
        )}
        <button
          disabled={!candidate || busy || reading}
          onClick={() => {
            const text = backupText(current);
            setExpected(text);
            setVerified(false);
            download(text, `恢复前备份_${Date.now()}.json`);
          }}
        >
          2. 下载当前数据备份
        </button>
        <label>
          3. 回选刚下载的恢复前备份
          <input
            key={expected}
            aria-label="回选恢复前备份"
            disabled={!expected || busy || reading}
            type="file"
            accept=".json"
            onChange={async (e) => {
              setVerified(false);
              setError("");
              const f = e.target.files?.[0];
              if (!f) return;
              setReading(true);
              try {
                if (f.size > new Blob([expected]).size + 10)
                  throw new Error("文件不匹配");
                if ((await f.text()) !== expected)
                  throw new Error("请回选刚下载的恢复前备份，不是旧备份");
                setVerified(true);
              } catch (e) {
                setError(e instanceof Error ? e.message : "备份校验失败");
              } finally {
                setReading(false);
              }
            }}
          />
        </label>
        {verified && <p className="success">备份内容校验通过，可以恢复。</p>}
      </section>
      <div className="actions">
        <button onClick={onClose} disabled={busy || reading}>
          关闭
        </button>
        <button
          className="danger"
          disabled={!candidate || !verified || busy || reading}
          onClick={() => {
            if (candidate && confirm("确认替换全部当前台账和历史周报？"))
              void onRestore(candidate);
          }}
        >
          确认替换全部数据
        </button>
      </div>
    </Modal>
  );
}
