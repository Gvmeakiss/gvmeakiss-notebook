import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL,fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import {spawnSync} from 'node:child_process';
const require=createRequire(import.meta.url),ts=require('typescript');
test('DDL迁移幂等、团队CAS独立与旧表保留',()=>{
 const result=spawnSync('python3',[fileURLToPath(new URL('./database_test.py',import.meta.url))],{encoding:'utf8'});
 assert.equal(result.status,0,result.stdout+result.stderr);
});
test('真实本机参考后端：旧台账保留、团队独立、并发冲突、不伪造成功',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'audit-storage-test-'));
 const storage=new Map();
 const savedWindow=Object.getOwnPropertyDescriptor(globalThis,'window'), savedNavigator=Object.getOwnPropertyDescriptor(globalThis,'navigator');
 let queue=Promise.resolve();
 Object.defineProperty(globalThis,'window',{configurable:true,value:{localStorage:{getItem:k=>storage.get(k)??null,setItem:(k,v)=>storage.set(k,v)}}});
 Object.defineProperty(globalThis,'navigator',{configurable:true,value:{locks:{request:(name,fn)=>{const p=queue.then(fn);queue=p.catch(()=>{});return p;}}}});
 try {
  const source=await readFile(new URL('../next-app/lib/audit/local-bff.ts',import.meta.url),'utf8');
  await writeFile(join(dir,'local.mjs'),ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022}}).outputText);
  const {mockExecSql:db}=await import(pathToFileURL(join(dir,'local.mjs')));
  const sql=(sqlKey,sqlParams=[])=>db({sqlFile:'team-workspace.sql.json',sqlKey,sqlParams});
  const old={revision:7,payload:'{"schemaVersion":2,"records":[],"snapshots":[]}',updated_at:'old'};
  storage.set('audit-workbench.localdb.audit_workspace.v1',JSON.stringify(old));
  assert.equal((await sql('getWorkspace',['default'])).result[0].revision,7);
  await sql('createTeam',['team-b','团队乙','{"schemaVersion":2,"records":[],"snapshots":[]}','date']);
  const [a,b]=await Promise.all([sql('saveWorkspace',[old.payload,'new','default',7]),sql('saveWorkspace',[old.payload,'new','team-b',0])]);
  assert.equal(a.affectedRows,1);assert.equal(b.affectedRows,1);
  const concurrent=await Promise.all([sql('saveWorkspace',[old.payload,'one','team-b',1]),sql('saveWorkspace',[old.payload,'two','team-b',1])]);
  assert.equal(concurrent.reduce((s,r)=>s+r.affectedRows,0),1);
  assert.equal((await sql('getWorkspace',['default'])).result[0].revision,8);
  assert.equal((await sql('getWorkspace',['team-b'])).result[0].revision,2);
  assert.equal((await sql('saveWorkspace',[old.payload,'x','unknown',0])).affectedRows,0);
  await assert.rejects(sql('createTeam',['c','团队乙',old.payload,'x']),/已存在/);
  await assert.rejects(db({sqlFile:'unknown',sqlKey:'saveWorkspace',sqlParams:[]}),/未登记/);
 } finally {
  if(savedWindow)Object.defineProperty(globalThis,'window',savedWindow);else delete globalThis.window;
  if(savedNavigator)Object.defineProperty(globalThis,'navigator',savedNavigator);else delete globalThis.navigator;
  await rm(dir,{recursive:true,force:true});
 }
});
test('团队读写接口绑定身份，旧文件可绑定，跨团队恢复被拒绝，CAS返回409',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'audit-api-test-'));
 const oldMode=process.env.NEXT_PUBLIC_DATA_MODE;process.env.NEXT_PUBLIC_DATA_MODE='platform';
 try {
  const source=await readFile(new URL('../next-app/lib/audit/workspace.ts',import.meta.url),'utf8');
  let code=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022}}).outputText;
  code=code.replace('"@/lib/client-fetch/client-db-fetch"','"./stub.mjs"').replace('"@/lib/audit/local-bff"','"./stub.mjs"').replace('"@/lib/domain/core"','"./core.mjs"');
  const coreURL=new URL('../next-app/lib/domain/legacy-core.js',import.meta.url).href,configURL=new URL('../next-app/lib/domain/config.js',import.meta.url).href;
  await writeFile(join(dir,'core.mjs'),`import {createCore} from ${JSON.stringify(coreURL)};import {CONFIG} from ${JSON.stringify(configURL)};export const K=createCore({CONFIG,crypto:globalThis.crypto});`);
  await writeFile(join(dir,'stub.mjs'),'export const mockExecSql=()=>{throw new Error("不能回退本机")}; export const clientDBFetch=p=>globalThis.auditTestDB(p);');
  await writeFile(join(dir,'api.mjs'),code);
  const api=await import(pathToFileURL(join(dir,'api.mjs')));
  const empty={schemaVersion:2,records:[],snapshots:[]};
  assert.equal(api.bindTeam(empty,'a').teamId,'a');assert.throws(()=>api.bindTeam({...empty,teamId:'b'},'a'),/其他团队/);
  globalThis.auditTestDB=p=>{assert.equal(p.sqlParams[0],'a');return {result:[{revision:4,payload:JSON.stringify(empty)}],affectedRows:0};};
  assert.equal((await api.loadWorkspace('a')).state.teamId,'a');
  globalThis.auditTestDB=p=>{assert.equal(p.sqlParams[2],'a');assert.equal(p.sqlParams[3],4);return {result:[],affectedRows:0};};
  await assert.rejects(api.saveWorkspace({...empty,teamId:'a'},4,'a'),e=>e.status===409);
  globalThis.auditTestDB=()=>{throw new Error('真实接口失败');};await assert.rejects(api.loadWorkspace('a'),/真实接口失败/);
 } finally {delete globalThis.auditTestDB;if(oldMode===undefined)delete process.env.NEXT_PUBLIC_DATA_MODE;else process.env.NEXT_PUBLIC_DATA_MODE=oldMode;await rm(dir,{recursive:true,force:true});}
});
