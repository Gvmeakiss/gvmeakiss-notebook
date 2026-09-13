import { enhancementFields } from "./enhancements.js";
/* ================= 可调整配置区 =================
 * 内网 AI 请优先修改本文件。id/key 是数据身份，已有数据后不要改名或删除；
 * label、颜色和展示字段可修改。新增字段请使用唯一英文 key，勿用 __proto__ 等保留名。
 * modules 省略表示全部模块共用；填写模块 id 数组可限定字段适用范围。
 */
export const CONFIG = {
  appName: "稽核工作进度看板",
  storageKey: "audit-kanban.v1", // 改名会切换到另一份本机台账，并不会迁移旧数据。
  schemaVersion: 2, // 修改数据格式时必须编写迁移逻辑，不能只改版本号。
  theme: { brand: "#FF6600", brandSoft: "#FFF4EC", brandText: "#C84B00" },
  ui: { defaultView: "list" }, // list 为紧凑列表，cards 为进度卡片；用户可在页面切换。
  modules: [
    { id: "project", label: "稽核项目", aliases: ["项目"] },
    { id: "risk-topic", label: "风险议题开发" },
    { id: "risk-system", label: "风险检测体系" },
    { id: "three-promotions", label: "三促" },
    { id: "three-letters", label: "三函" },
    { id: "loss-recovery", label: "挽损" },
    { id: "other", label: "其他" },
  ],
  legacyModules: [
    {
      id: "promotion",
      label: "待归类（三促／三函／挽损）",
      aliases: ["三促／三函／挽损"],
    },
  ],
  fields: [
    ...enhancementFields,
    {
      key: "name",
      label: "名称",
      type: "text",
      required: true,
      maxLength: 200,
    },
    {
      key: "owner",
      label: "负责人／参与人员",
      aliases: ["负责人"],
      type: "text",
      required: true,
      maxLength: 500,
    },
    {
      key: "progressPercent",
      label: "项目进度（%）",
      type: "number",
      min: 0,
      max: 100,
      step: 1,
      importOptional: true,
    },
    // 历史字段不再显示或录入；保留兼容原 JSON / Excel，避免丢失已有文字。
    {
      key: "tracking",
      label: "工作跟踪（历史保留）",
      aliases: ["工作跟踪"],
      type: "textarea",
      maxLength: 4000,
      legacy: true,
      importOptional: true,
    },
    {
      key: "progress",
      label: "目前进度描述",
      aliases: ["现阶段进展"],
      type: "textarea",
      maxLength: 4000,
    },
    {
      key: "dueDate",
      label: "项目整体交付日期",
      aliases: ["预计交付日期"],
      type: "date",
      required: true,
    },
    {
      key: "nextPlan",
      label: "下一阶段工作内容",
      aliases: ["下一步计划"],
      type: "textarea",
      maxLength: 4000,
    },
    { key: "completed", label: "是否完成", type: "boolean", required: true },
    {
      key: "previousStageContent",
      label: "已完成阶段内容",
      type: "textarea",
      maxLength: 4000,
      importOptional: true,
    },
    {
      key: "previousStageCompletedDate",
      label: "已完成阶段完成日期",
      type: "date",
      importOptional: true,
    },
    {
      key: "currentStageTask",
      label: "本阶段项目任务",
      type: "textarea",
      maxLength: 4000,
      importOptional: true,
    },
    {
      key: "currentStageDueDate",
      label: "本阶段预期完成时间",
      type: "date",
      importOptional: true,
    },
  ],
  // 颜色可以调整；状态 key 和计算优先级由 core.js 维护。
  statuses: {
    normal: { label: "未逾期", color: "#18745b", background: "#e6f3eb" },
    overdue: { label: "已逾期", color: "#bd4637", background: "#fff0eb" },
    completed: { label: "已完成", color: "#316baa", background: "#eaf1fc" },
  },
  board: {
    textFields: ["currentStageTask", "progress"], // 卡片正文显示顺序；进度百分比单独显示为进度条。
    showEmptyModules: true,
    defaultSort: "dueDate", // 支持 dueDate（交付日期升序）、updatedAt（更新倒序）。
  },
  limits: {
    maxFileBytes: 15 * 1024 * 1024,
    maxRecords: 5000,
    maxSnapshots: 100,
  },
  excel: {
    sheetName: "工作台账",
    idLabel: "唯一编号",
    moduleLabel: "模块",
    updatedLabel: "更新时间",
    statusLabel: "实际状态（只读）",
  },
};
