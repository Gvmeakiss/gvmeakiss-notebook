// Generate downloadable Excel only from the bundled fictional JSON fixture.
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {createRequire} from 'node:module';
import {CONFIG} from '../next-app/lib/domain/config.js';
import {createCore} from '../next-app/lib/domain/legacy-core.js';
import {createExcel} from '../next-app/lib/domain/legacy-excel.js';
const require=createRequire(import.meta.url),X=require('../next-app/public/vendor/xlsx.full.min.js');
const K=createCore({CONFIG,crypto:globalThis.crypto});
const state=K.validateBackup(JSON.parse(readFileSync(new URL('../next-app/public/demo/fictional-audit.json',import.meta.url),'utf8')));
const E=createExcel({CONFIG,KanbanCore:K,XLSX:X});
const out=new URL('../next-app/public/demo/fictional-audit.xlsx',import.meta.url);
writeFileSync(out,Buffer.from(X.write(E.workbook(state.records,{teamId:'default'}),{type:'array',bookType:'xlsx'})));
console.log('Generated fictional demo Excel');
