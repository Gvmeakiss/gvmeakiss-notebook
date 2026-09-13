// 同源生成独立说明页和 Markdown 手册，避免与应用弹窗内容不一致。
import {writeFileSync} from 'node:fs';
import {helpSections,helpUpdatedAt} from '../next-app/lib/domain/help-content.js';
const escape=value=>value.replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const sections=helpSections.map(s=>`<details id="${s.id}"><summary><span class="tag">${escape(s.tag)}</span><span class="caption">${escape(s.title)}</span></summary><div class="body">${s.paragraphs.map(p=>`<p>${escape(p)}</p>`).join('\n')}</div></details>`).join('\n');
const html=`<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>稽核工作台使用说明</title><style>
body{margin:0;background:#f5f6f8;color:#263040;font:15px/1.85 -apple-system,BlinkMacSystemFont,"Microsoft YaHei",sans-serif}main{max-width:900px;margin:28px auto;padding:28px;background:white;border-top:4px solid #d4651c}h1{font-size:26px}details{border:1px solid #e0e4e9;border-radius:8px;margin:12px 0}summary{cursor:pointer;padding:14px}summary:hover{background:#fff8f1}summary:focus-visible{outline:2px solid #a64708}.tag{display:inline-block;background:#fff0e4;color:#914315;border-radius:5px;padding:2px 8px;margin:0 12px 0 4px;font-weight:650}.caption{font-size:14px;color:#566174}.body{border-top:1px solid #edf0f3;padding:2px 20px 14px}.muted{color:#657084}@media(max-width:600px){main{margin:0;padding:18px}h1{font-size:23px}.caption{display:block;margin-left:24px}.body{padding:2px 12px 12px}}
</style></head><body><main><h1>稽核工作台使用说明</h1><p class="muted">按标签查找，点击展开；再次点击收起。更新于 ${helpUpdatedAt}。</p>${sections}</main></body></html>`;
writeFileSync(new URL('../next-app/public/使用说明.html',import.meta.url),html);
const md=`# 稽核工作台 · 使用说明\n\n更新于 ${helpUpdatedAt}。应用左侧“使用说明”按下列标签分类，默认全部折叠。\n\n`+helpSections.map(s=>`<details>\n<summary>${s.tag}｜${s.title}</summary>\n\n${s.paragraphs.join('\n\n')}\n\n</details>`).join('\n\n')+'\n';
writeFileSync(new URL('../docs/使用说明.md',import.meta.url),md);
