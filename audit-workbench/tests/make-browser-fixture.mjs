// 仅生成虚构浏览器验证文件，不读取真实业务台账。
import {writeFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {CONFIG} from '../next-app/lib/domain/config.js';
import {createCore} from '../next-app/lib/domain/legacy-core.js';
import {createExcel} from '../next-app/lib/domain/legacy-excel.js';
const require=createRequire(import.meta.url),X=require('../next-app/public/vendor/xlsx.full.min.js');
const K=createCore({CONFIG,crypto:globalThis.crypto}),E=createExcel({CONFIG,KanbanCore:K,XLSX:X});
const r={id:'d4a1df4f-0db2-4114-b60c-2a2b24f25c84',module:'loss-recovery',name:'自动验证挽损项目',owner:'验证甲',dueDate:'2026-09-30',completed:false,updatedAt:'2026-09-12T00:00:00.000Z',previousStageContent:'第二阶段追回款项\n已确认部分回款',previousStageCompletedDate:'2026-09-12',currentStageTask:'第三阶段核对结案',currentStageDueDate:'',progress:'Excel手工补充验证',nextPlan:'',recoveryKey:'AUTO-001',recoveryExpected:1500,recoveryActual:750,recoveryEntries:[{id:'test-entry',date:'2026-09-12',amount:750,method:'资金追回',evidence:'Excel补录确认单'}]};
writeFileSync('tests/artifacts/虚构Excel补录验证.xlsx', Buffer.from(X.write(E.workbook([r],{teamId:'default'}),{type:'array',bookType:'xlsx'})));
writeFileSync('tests/artifacts/虚构跨团队拒绝验证.xlsx', Buffer.from(X.write(E.workbook([{...r,teamId:'foreign-team'}],{teamId:'foreign-team'}),{type:'array',bookType:'xlsx'})));
