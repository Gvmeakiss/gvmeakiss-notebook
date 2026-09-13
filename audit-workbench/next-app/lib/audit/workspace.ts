/* =============================================================================
 * 业务数据访问层：部门台账的读取与原子保存（文档型 + revision 乐观锁）。
 *
 * 规范契合点：所有 SQL 均经 db/sql/team-workspace.sql.json 预定义，前端仅以
 *   { sqlFile, sqlKey, sqlParams } 引用，不拼接 SQL（规范 §1.6 决策2 / §3.3）。
 * 双模式：
 *   platform（须另行接入）      → clientDBFetch → BFF → Gateway → SQLite（公司环境）
 *   local-reference（默认）→ mockExecSql（本机 localStorage 参考后端，本机验证用）
 * 并发：保存携带 expectedRevision，服务端/参考后端做 CAS，affectedRows≠1 即冲突（409）。
 * ========================================================================== */
import {
  clientDBFetch,
  type DBFetchPayload,
  type DBExecResult,
} from "@/lib/client-fetch/client-db-fetch";
import { mockExecSql } from "@/lib/audit/local-bff";
import { K } from "@/lib/domain/core";
import type { AuditState, Envelope, Team } from "@/types/audit";

export const dataMode = process.env.NEXT_PUBLIC_DATA_MODE || "local-reference";

const SQL_FILE = "team-workspace.sql.json";

/** 统一执行入口：按数据模式路由到真 BFF 或本机参考后端。 */
async function execDB(payload: DBFetchPayload): Promise<DBExecResult> {
  if (dataMode === "local-reference") return mockExecSql(payload);
  if (dataMode === "platform") return clientDBFetch(payload);
  throw new Error(`数据模式无效：${dataMode}`);
}

function toEnvelope(revision: number, state: unknown, teamId: string): Envelope {
  if (!Number.isSafeInteger(revision) || revision < 0) {
    throw new Error("服务端返回版本无效");
  }
  return { revision, state: bindTeam(K.validateBackup(state), teamId) };
}

/** 读取整份部门台账（records + snapshots）。 */
export async function loadWorkspace(teamId = "default"): Promise<Envelope> {
  validateTeamId(teamId);
  const { result } = await execDB({
    sqlFile: SQL_FILE,
    sqlKey: "getWorkspace",
    sqlParams: [teamId],
  });
  if (!result.length) throw new Error("工作区未初始化");
  const row = result[0] as { revision: number; payload: string };
  return toEnvelope(Number(row.revision), JSON.parse(String(row.payload)), teamId);
}

/** 原子保存台账；expectedRevision 不匹配时抛出带 status=409 的 Error。 */
export async function saveWorkspace(
  state: AuditState,
  expectedRevision: number,
  teamId = "default",
): Promise<Envelope> {
  validateTeamId(teamId);
  const validated = K.validateBackup(bindTeam(state, teamId));
  if (!Number.isSafeInteger(expectedRevision) || expectedRevision < 0) {
    throw new Error("版本号无效");
  }
  const updatedAt = new Date().toISOString();
  const { affectedRows } = await execDB({
    sqlFile: SQL_FILE,
    sqlKey: "saveWorkspace",
    sqlParams: [JSON.stringify(validated), updatedAt, teamId, expectedRevision],
  });
  if (affectedRows !== 1) {
    const error = new Error("台账已被其他人更新，请先下载待保存数据，再刷新并合并");
    Object.assign(error, { status: 409 });
    throw error;
  }
  return toEnvelope(expectedRevision + 1, validated, teamId);
}

function validateTeamId(id: string) {
  if (!/^[A-Za-z0-9_-]{1,100}$/.test(id)) throw new Error("团队编号无效");
}
export function bindTeam(state: AuditState, teamId: string): AuditState {
  validateTeamId(teamId);
  if (state.teamId && state.teamId !== teamId) throw new Error("不能将其他团队的备份写入当前团队");
  for (const r of [...state.records, ...state.snapshots.flatMap(s => s.records)])
    if (r.teamId && r.teamId !== teamId) throw new Error("文件包含其他团队记录，请切换所属团队");
  return { ...state, teamId, records: state.records.map(r => ({ ...r, teamId })) };
}
export async function listTeams(): Promise<Team[]> {
  const { result } = await execDB({sqlFile: SQL_FILE, sqlKey: "listTeams", sqlParams: []});
  return result.map(row => {
    const r = row as {team_id: string; name: string};
    validateTeamId(r.team_id);
    return {id:r.team_id, name:r.name};
  });
}
export async function createTeam(name: string): Promise<Team> {
  name = name.trim();
  if (!name || name.length > 60) throw new Error("团队名称须为1—60字");
  const id = K.id();
  const state = {...K.emptyState(), teamId:id};
  const { affectedRows } = await execDB({sqlFile:SQL_FILE, sqlKey:"createTeam", sqlParams:[id,name,JSON.stringify(state),new Date().toISOString()]});
  if (affectedRows !== 1) throw new Error("团队创建失败，请刷新检查是否已存在");
  return {id,name};
}
