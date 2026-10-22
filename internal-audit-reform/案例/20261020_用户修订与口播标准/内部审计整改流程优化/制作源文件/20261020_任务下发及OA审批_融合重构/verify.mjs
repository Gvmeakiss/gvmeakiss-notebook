import fs from 'node:fs/promises';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
const require=createRequire(import.meta.url);
const font='/System/Library/AssetsV2/com_apple_MobileAsset_Font8/88d6cc32a907955efa1d014207889413890573be.asset/AssetData/Kaiti.ttc';
require('@napi-rs/canvas').GlobalFonts.registerFromPath(font,'Kaiti SC');
try{require('skia-canvas').FontLibrary.use('Kaiti SC',[font]);}catch{}
const {FileBlob,PresentationFile}=await import('@oai/artifact-tool');
const workspace=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../..');
const pptx=path.join(workspace,'内部审计整改流程优化/最终交付/20261020_任务下发及OA审批_融合重构/任务下发与OA审批_融合重构版.pptx');
const deck=await PresentationFile.importPptx(await FileBlob.load(pptx));
if(deck.slides.items.length!==2)throw new Error('Expected two slides');
for (const [i,slide] of deck.slides.items.entries()){
 const png=await deck.export({slide,format:'png',scale:1.5});
 await fs.writeFile(path.join(workspace,`归档/20261020_任务下发及OA审批融合重构核对/final-slide-${i+1}.png`),new Uint8Array(await png.arrayBuffer()));
}
console.log('Final PPTX re-imported and both slides rendered');
