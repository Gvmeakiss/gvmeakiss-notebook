import fs from 'node:fs/promises';
import path from 'node:path';
import {createRequire} from 'node:module';
import {fileURLToPath, pathToFileURL} from 'node:url';
const require=createRequire(import.meta.url);
process.env.RUNTIME_NODE_MODULES='/Users/aatrox/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules';
const FONT='Kaiti SC';
const fontPath='/System/Library/AssetsV2/com_apple_MobileAsset_Font8/88d6cc32a907955efa1d014207889413890573be.asset/AssetData/Kaiti.ttc';
const {GlobalFonts}=require('@napi-rs/canvas');
if (!GlobalFonts.registerFromPath(fontPath,FONT)) throw new Error('Kaiti font registration failed');
try { require('skia-canvas').FontLibrary.use(FONT,[fontPath]); } catch {}
const {Presentation,PresentationFile}=await import('@oai/artifact-tool');
const skill='/Users/aatrox/.codex/plugins/cache/openai-primary-runtime/presentations/26.1015.12040/skills/presentations';
const {finalizePresentation}=await import(pathToFileURL(path.join(skill,'container_tools/artifact_tool_utils.mjs')).href);
const here=path.dirname(fileURLToPath(import.meta.url));
const workspace=path.resolve(here,'../../..');
const checks=path.join(workspace,'归档/20261020_任务下发及OA审批融合重构核对');
const output=path.join(workspace,'内部审计整改流程优化/最终交付/20261020_任务下发及OA审批_融合重构/任务下发与OA审批_融合重构版.pptx');
await fs.mkdir(checks,{recursive:true});
await fs.mkdir(path.dirname(output),{recursive:true});
const deck=Presentation.create({slideSize:{width:1280,height:720}});
const C={orange:'#F34716',red:'#D62B13',ink:'#161616',grey:'#909090',light:'#FFF4EB'};
function box(slide,name,x,y,w,h,fill='none',stroke='none',radius=0){
 return slide.shapes.add({name,geometry:'rect',position:{left:x,top:y,width:w,height:h},fill,line:{fill:stroke,width:stroke==='none'?0:1},...(radius?{borderRadius:radius}:{})});
}
function text(slide,name,content,x,y,w,h,size=22,color=C.ink,bold=false,align='left'){
 const s=box(slide,name,x,y,w,h);
 s.text=content;s.text.style={fontSize:size,typeface:FONT,color,bold,alignment:align,verticalAlignment:'middle',autoFit:'none',wrap:'square',insets:0,lineSpacing:1.15};
 return s;
}
function base(title,n){
 const s=deck.slides.add();s.background.fill='#FFFFFF';
 text(s,'页面标题',title,44,22,1192,48,33,C.ink,true);
 box(s,'标题下划线',44,77,1192,2,C.red);
 box(s,'页脚分隔线',0,687,1280,1.3,C.red);
 text(s,'团队署名','专项稽核团队',44,693,600,22,15);
 text(s,'页码',`${n}/2`,1160,693,76,22,15,C.ink,false,'right');
 return s;
}
function line(slide,from,to,color=C.orange){
 return slide.shapes.connect(from,to,{kind:'straight',fromSide:'right',toSide:'left',line:{fill:color,width:1.7},tail:{type:'triangle',width:'sm',length:'sm'}});
}
function nativeTable(slide,name,values,y,widths,heights,accentColumn=-1){
 const t=slide.tables.add({rows:values.length,columns:widths.length,left:60,top:y,width:1160,height:heights.reduce((a,b)=>a+b,0),columnWidths:widths,values});
 t.styleOptions={headerRow:true,bandedRows:false};t.borders.assign({fill:'#929292',width:.75,style:'solid'});
 for(let r=0;r<values.length;r++){
  t.rows[r].height=heights[r];
  for(let c=0;c<widths.length;c++){
   const cell=t.getCell(r,c);cell.fill=r===0?C.orange:'#FFFFFF';
   cell.text.style={fontSize:23,typeface:FONT,color:r===0?'#FFFFFF':c===accentColumn?C.red:C.ink,bold:r===0||c===accentColumn,alignment:'center',verticalAlignment:'middle',autoFit:'none',wrap:'square',insets:5,lineSpacing:1.1};
  }
 }
 return t;
}
const s1=base('01 任务下发—启动与反馈',1);
text(s1,'发起接收标题','发起与接收',60,102,1160,33,25,C.ink,true);
nativeTable(s1,'发起接收表',[
 ['事项类型','发起人','接收对象'],
 ['稽核项目','稽核项目组','被审计单位责任人'],
 ['三函事项','三函提交人（主审）','责任部门']
],147,[250,455,455],[46,54,54]);
text(s1,'时点时效标题','发送节点与整改措施反馈时效',60,315,1160,33,25,C.ink,true);
nativeTable(s1,'发送时效表',[
 ['事项来源','发送时点','整改措施反馈时效'],
 ['常规及专项稽核项目','处罚小组结束后立即发送','5个工作日'],
 ['指令函','评审会通过后发送','5个工作日'],
 ['警示函','评审会通过后发送','10个工作日'],
 ['知询函','稽核部公邮发出时同步发送','10个工作日']
],359,[280,600,280],[46,54,54,54,54],2);
text(s1,'反馈附带要求','成因分析随整改措施一并反馈',60,637,1160,32,23,C.ink,false);
s1.speakerNotes.text='来源为经理修改版PPT第10页及用户2026年10月20日的补充、融合重构意见。将共同的发起接收信息按稽核项目、三函分别列一次，发送时点与反馈时效按四类来源列示。指令函、常规及专项稽核项目为5个工作日，警示函和知询函为10个工作日。材料名称集中在第二页一次展示，保留成因分析随措施一并反馈。本页不重复罗列交付材料、反馈要求和旧邮件报送名单，报送关系在第二页通过OA审批与传阅呈现。未新增时限起算规则。';

const s2=base('01 任务下发—OA审批与传阅',2);
const seq=['整改措施\n收集完毕','整改措施定稿','系统内下发\n整改任务','OA审批'];
const proc=seq.map((t,i)=>{
 const x=60+i*299;
 const b=box(s2,`前置顺序${i+1}`,x,110,263,66,i===3?C.orange:'#FFFFFF',C.orange,8);
 b.text=t;b.text.style={typeface:FONT,fontSize:23,color:i===3?'#FFFFFF':C.ink,bold:i===3,alignment:'center',verticalAlignment:'middle',autoFit:'none',insets:5};return b;
});
for(let i=0;i<3;i++)line(s2,proc[i],proc[i+1]);
const material=text(s2,'OA审批材料','审批材料：整改措施通知书、整改措施表',60,207,1160,37,25,C.ink,true);
material.text.get('整改措施通知书').color=C.red;
material.text.get('整改措施表').color=C.red;
function role(name,content,x,y,w){
 const b=box(s2,name,x,y,w,80,'#FFFFFF',C.orange,8);
 b.text=content;b.text.style={typeface:FONT,fontSize:22,color:C.ink,alignment:'center',verticalAlignment:'middle',autoFit:'none',insets:5,lineSpacing:1.12};return b;
}
text(s2,'机构端标签','机构端',430,274,362,30,25,C.red,true);
text(s2,'总部端标签','总部端',430,442,362,30,25,C.red,true);
const author=role('共同审批1','项目主审',60,396,140);
const manager=role('共同审批2','项目经理',236,396,140);
const complianceA=role('机构端审批3','机构法律合规部\n经理',430,312,178);
const leaderA=role('机构端审批4','二级机构\n一把手',642,312,150);
const complianceB=role('总部端审批3','总部法律合规室\n经理',430,480,178);
const leaderB=role('总部端审批4','整改责任\n部门长',642,480,150);
const senior=role('共同审批5','专项稽核团队\n高级经理',850,396,170);
const audit=role('共同审批6','产险审计\n责任人',1060,396,160);
line(s2,author,manager);line(s2,complianceA,leaderA);line(s2,complianceB,leaderB);line(s2,senior,audit);
function branch(from,to){
 s2.shapes.connect(from,to,{kind:'elbow3',fromSide:'right',toSide:'left',line:{fill:C.orange,width:1.7},tail:{type:'triangle',width:'sm',length:'sm'}});
}
branch(manager,complianceA);branch(manager,complianceB);branch(leaderA,senior);branch(leaderB,senior);
const circulation=box(s2,'共同传阅对象',1045,574,190,76,C.light,'#E9AA87',8);
circulation.text='条线室经理\n问责室经理';
circulation.text.style={typeface:FONT,fontSize:23,color:C.ink,alignment:'center',verticalAlignment:'middle',autoFit:'none',insets:5};
s2.shapes.connect(audit,circulation,{kind:'straight',fromSide:'bottom',toSide:'top',line:{fill:C.orange,width:1.7},tail:{type:'triangle',width:'sm',length:'sm'}});
text(s2,'传阅关系','传阅',1153,505,70,32,23,C.red,true);
s2.speakerNotes.text='按用户融合重构要求，共同审批人只出现一次，机构端、总部端仅在不同的两个审批环节分支，随后汇合。完整路径仍分别为：项目主审→项目经理→机构法律合规部经理→二级机构一把手→专项稽核团队高级经理→产险审计责任人；项目主审→项目经理→总部法律合规室经理→整改责任部门长→专项稽核团队高级经理→产险审计责任人。之后向条线室经理及问责室经理传阅。两项材料集中在本页列示，原交付材料区和邮件报送名单不再与OA模块重复展示。该展示合并不自行规定邮件制度取消，也不将旧抄送对象逐一等同于新的审批岗位。';

for(let i=0;i<deck.slides.items.length;i++){
 const slide=deck.slides.items[i];
 const png=await deck.export({slide,format:'png',scale:1.5});
 await fs.writeFile(path.join(checks,`slide-${i+1}.png`),new Uint8Array(await png.arrayBuffer()));
 const layout=await slide.export({format:'layout'});
 await fs.writeFile(path.join(checks,`slide-${i+1}.layout.json`),await layout.text());
}
const draft=path.join(checks,'candidate.pptx');
await (await PresentationFile.exportPptx(deck)).save(draft);
const final=await finalizePresentation({
 explicitTotalSlideCount:2,requiredNativeTableOwnerSlides:[1],requiredNativeChartOwnerSlides:[],
 workspaceDir:workspace,candidatePath:draft,finalPath:output,
 pythonExecutable:'/Users/aatrox/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3',
 integrityValidatorPath:path.join(skill,'container_tools/inspect_presentation_package_integrity.py'),
 layoutValidatorPath:path.join(skill,'container_tools/inspect_presentation_layout_geometry.py'),
 layoutArgs:['--expected-slide-size-emu','12192000,6858000','--validate-bullet-geometry','--validate-heading-fit','--require-native-table-slide','1'],
 fontPolicy:{basis:'design',families:[FONT]},verifyArtifactToolImport:true,
 receiptPath:path.join(checks,'validation.json')
});
console.log(JSON.stringify({output,final},null,2));
