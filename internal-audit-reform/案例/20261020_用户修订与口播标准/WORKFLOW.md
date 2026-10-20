# 照片与 PDF 材料处理 Workflow

执行入口：[完整工作流](./工作流/照片与PDF材料审阅.md)

Git 复用入口：[仓库 main 工作流](https://github.com/Gvmeakiss/gvmeakiss-notebook/blob/main/internal-audit-reform/workflows/照片与PDF材料审阅.md)

1. 首次接收材料，先清点版本、文件、页数与顺序，完整审阅全部页面。
2. 整理为 `资料索引/<材料ID>/`：INDEX、逐页原文与摘要、结构关系、VISUAL_SPEC、来源指纹及未决事项。
3. 分别核对文字、结构和配色；照片估测信息明确标注，不能用 OCR 成功或转换出 MD 代替视觉理解核对。
4. 后续先读 INDEX，再检索相关页 MD；信息密集、有歧义或需要新的视觉细节时，才回查对应图片/区域。
5. 回查后立即更新文本记录；来源更新时增量核对，最终验收查看新成品。

模板：[索引](./工作流/templates/INDEX.template.md)、[逐页记录](./工作流/templates/PAGE.template.md)、[视觉记录](./工作流/templates/VISUAL_SPEC.template.md)、[来源清单](./工作流/templates/manifest.example.json)

依据：[阅读顺序、结构化 Markdown、配色与对比度资料](./工作流/知识与方法来源.md)

原文与摘要分开，原文与用户后续展示修改分开。最终交付目录只保存成品。当前用户已授权将本轮业务材料原样同步私有仓库 `Gvmeakiss/gvmeakiss-notebook`；同步前核验隐私状态，不把资料正文放到公开个人主页。

## 口播与当前材料入口

- [资料索引](./资料索引/INDEX.md)：先确认业务来源与表达样本的版本和用途
- [口播稿撰写标准](./工作流/口播稿撰写标准.md)：以用户修改稿为语言基准，先核业务，再通读顺句，保留完整逻辑、自然转场和必要归纳
- 用户确认的是表达标准，不自动覆盖PPT中的最新数字、角色、页序和流程
