"use client";
// 本机团队分区参考实现。不同团队分开存储，同源标签页通过 Web Locks 串行执行 CAS。
import type { DBFetchPayload, DBExecResult } from '@/lib/client-fetch/client-db-fetch';
const LEGACY_KEY = 'audit-workbench.localdb.audit_workspace.v1';
const TEAMS_KEY = 'audit-workbench.teams.v1';
interface Row { revision:number; payload:string; updated_at:string; }
interface TeamRow {team_id:string; name:string;}
function store() {
  if (typeof window === 'undefined') throw new Error('本机参考模式仅在浏览器可用');
  return window.localStorage;
}
function teams(): TeamRow[] {
  return JSON.parse(store().getItem(TEAMS_KEY) || '[{"team_id":"default","name":"原稽核团队"}]');
}
const key = (id: string) => id === 'default' ? LEGACY_KEY : 'audit-workbench.team.'+id;
function read(id:string): Row | null {
  if (!teams().some(t => t.team_id === id)) return null;
  const raw = store().getItem(key(id));
  if (raw) return JSON.parse(raw);
  if (id !== 'default') throw new Error('团队数据缺失，请恢复备份，不能初始化覆盖');
  const init = {revision:0,payload:'{"schemaVersion":2,"records":[],"snapshots":[]}',updated_at:new Date().toISOString()};
  store().setItem(key(id),JSON.stringify(init));
  return init;
}
function run(p:DBFetchPayload): DBExecResult {
  if (p.sqlFile !== 'team-workspace.sql.json') throw new Error('未登记的业务 SQL 文件');
  if (p.sqlKey === 'listTeams') return {result:teams(),affectedRows:0};
  if (p.sqlKey === 'createTeam') {
    const [id,name,payload,date] = p.sqlParams.map(String), list = teams();
    if (list.some(t => t.team_id === id || t.name === name)) throw new Error('团队名称已存在，请直接进入');
    // 写入失败不会建立可见的空团队。注册表是提交点。
    store().setItem(key(id),JSON.stringify({revision:0,payload,updated_at:date}));
    store().setItem(TEAMS_KEY,JSON.stringify([...list,{team_id:id,name}]));
    return {result:[],affectedRows:1};
  }
  if (p.sqlKey === 'getWorkspace') {
    const row = read(String(p.sqlParams[0]));
    return {result:row ? [row] : [],affectedRows:0};
  }
  if (p.sqlKey === 'saveWorkspace') {
    const [payload,date,id,revision] = p.sqlParams, row = read(String(id));
    if (!row || row.revision !== revision) return {result:[],affectedRows:0};
    if (new TextEncoder().encode(String(payload)).byteLength > 8*1024*1024) throw new Error('台账超过本机容量，请备份后整理');
    store().setItem(key(String(id)),JSON.stringify({revision:row.revision+1,payload:String(payload),updated_at:String(date)}));
    return {result:[],affectedRows:1};
  }
  throw new Error('未登记的 SQL 操作');
}
export async function mockExecSql(payload:DBFetchPayload): Promise<DBExecResult> {
  if (!navigator.locks) throw new Error('本机并发保护需要支持 Web Locks 的浏览器及 localhost/HTTPS 地址');
  return navigator.locks.request('audit-workbench-local-db', () => run(payload));
}
