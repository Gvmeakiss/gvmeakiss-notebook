import test from 'node:test';
import assert from 'node:assert/strict';
import {overdueGroups,weeklyTrend,recoveryMonths} from '../next-app/lib/domain/dashboard.js';
test('逾期分组边界、已完成和归档排除，当天不逾期',()=>{
 const today='2026-09-12';
 const rows=['2026-09-12','2026-09-11','2026-09-05','2026-09-04','2026-08-13','2026-08-12'].map((dueDate,i)=>({id:String(i),dueDate,completed:false}));
 const groups=overdueGroups([...rows,{...rows[1],id:'done',completed:true},{...rows[1],id:'arch',archivedAt:'2026-09-12'}],today);
 assert.deepEqual(groups.map(g=>g.records.length),[2,2,1]);
 assert.deepEqual(groups[0].records.map(r=>r.id),['2','1']);
 assert.deepEqual(rows.map(r=>r.id),['0','1','2','3','4','5']);
});
test('趋势同周取最新、不补造缺周，按冻结状态计算并排除当时归档',()=>{
 const snapshots=[{id:'new',week:'2026-09-07',savedAt:'2026-09-09',records:[{frozenStatus:'normal',dueDate:'2020-01-01'},{frozenStatus:'completed',archivedAt:'2026-09-01'}]}, {id:'old',week:'2026-09-07',savedAt:'2026-09-08',records:[]},{id:'earlier',week:'2026-08-24',savedAt:'2026-08-25',records:[{frozenStatus:'overdue'}]}];
 const rows=weeklyTrend(snapshots);assert.deepEqual(rows.map(r=>r.id),['earlier','new']);assert.equal(rows[1].normal,1);assert.equal(rows[1].total,1);assert.equal(rows[1].completed,0);
});
test('月度金额按分汇总，不将累计金额再次计入，方式筛选且缺月不补零',()=>{
 const rows=[{module:'loss-recovery',recoveryActual:1000,recoveryEntries:[{date:'2026-01-10',amount:0.1,method:'资金追回'},{date:'2026-01-12',amount:0.2,method:'资金追回'},{date:'2026-03-01',amount:5,method:'核减支付'}]},{module:'project',recoveryEntries:[{date:'2026-02-01',amount:999}]},{module:'loss-recovery',recoveryActual:500}];
 assert.deepEqual(recoveryMonths(rows),[{month:'2026-01',amount:0.3},{month:'2026-03',amount:5}]);assert.deepEqual(recoveryMonths(rows,'核减支付'),[{month:'2026-03',amount:5}]);assert.deepEqual(recoveryMonths([]),[]);
});
