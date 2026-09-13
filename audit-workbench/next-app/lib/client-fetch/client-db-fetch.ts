// Public integration boundary. Deliberately contains no private API, token or endpoint.
export interface DBFetchPayload { sqlFile:string; sqlKey:string; sqlParams:unknown[]; }
export interface DBExecResult { result:unknown[]; affectedRows:number; }
export async function clientDBFetch(_payload:DBFetchPayload):Promise<DBExecResult> {
  throw new Error("平台数据接口尚未配置；公开演示请使用 local-reference 模式");
}
