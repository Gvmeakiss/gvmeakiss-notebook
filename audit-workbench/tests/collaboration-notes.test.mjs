import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {CONFIG} from '../next-app/lib/domain/config.js';
import {createCore} from '../next-app/lib/domain/legacy-core.js';
import {createExcel} from '../next-app/lib/domain/legacy-excel.js';
import {attentionReasons} from '../next-app/lib/domain/enhancements.js';
const K=createCore({CONFIG,crypto:globalThis.crypto}),require=createRequire(import.meta.url),X=require('../next-app/public/vendor/xlsx.full.min.js'),E=createExcel({CONFIG,KanbanCore:K,XLSX:X});
const record=(extra={})=>({id:'notes-test',module:'project',name:'虚构进展',owner:'验证甲',dueDate:'2026-12-31',completed:false,updatedAt:'2026-09-12T00:00:00.000Z',progress:'核对中',...extra});
test('新字段可选，协作状态不改变自动逾期规则，跟进到期进入协调提醒',()=>{
 assert.deepEqual(K.validateRecord(record()),[]);
 const r=record({collaborationStatus:'暂缓',followUpDate:'2026-09-12',remarks:'等待资料'});
 assert.deepEqual(K.validateRecord(r),[]);assert.equal(K.status(r,'2026-09-12'),'normal');assert.ok(attentionReasons(r,'2026-09-12').includes('跟进到期'));
 assert.equal(K.status({...r,dueDate:'2026-09-11'},'2026-09-12'),'overdue');
 assert.ok(K.validateRecord({...r,collaborationStatus:'任意状态'}).length);assert.ok(K.validateRecord({...r,followUpDate:'bad'}).length);assert.ok(K.validateRecord({...r,remarks:'长'.repeat(2001)}).length);
});
test('新字段Excel与JSON往返，旧文件导入保留、显式空值允许清除',()=>{
 const r=record({collaborationStatus:'等待复核',followUpDate:'2026-09-20',remarks:'第一行\n第二行'});
 const got=E.read(X.write(E.workbook([r],{teamId:'default'}),{type:'array',bookType:'xlsx'}),{teamId:'default'})[0];
 for(const k of ['collaborationStatus','followUpDate','remarks'])assert.equal(got[k],r[k]);
 assert.equal(K.validateBackup({schemaVersion:2,records:[r],snapshots:[]}).records[0].remarks,r.remarks);
 const plan=K.prepareMerge([r],[record({progress:'旧文件更新进展'})]);const merged=K.applyMerge([r],plan,{[r.id]:'incoming'})[0];assert.equal(merged.remarks,r.remarks);assert.equal(merged.collaborationStatus,r.collaborationStatus);
 const empty=K.prepareMerge([r],[{...r,remarks:''}]);assert.equal(K.applyMerge([r],empty,{[r.id]:'incoming'})[0].remarks,'');
});
test('后续备注和协作状态修改不改变已有周快照',()=>{
 const r=record({remarks:'留档时的备注',collaborationStatus:'等待资料'}),snapshot=K.snapshot([r]);r.remarks='新备注';r.collaborationStatus='推进中';assert.equal(snapshot.records[0].remarks,'留档时的备注');assert.equal(snapshot.records[0].collaborationStatus,'等待资料');
});
