export type Status = "normal" | "overdue" | "completed";
export interface StageHistoryEntry {
  id: string; recordedAt: string; reason: string;
  previousStageContent?: string; previousStageCompletedDate?: string;
  currentStageTask?: string; currentStageDueDate?: string; progress?: string; nextPlan?: string;
}
export interface RecoveryEntry {
  id: string; date: string; amount: number; method: string; evidence: string; note?: string;
}
export interface Team { id: string; name: string; }
export interface AuditRecord {
  collaborationStatus?: string;
  followUpDate?: string;
  remarks?: string;
  teamId?: string;
  archivedAt?: string;
  stageHistory?: StageHistoryEntry[];
  attention?: string; blocker?: string; supportNeeded?: string;
  outcomeSummary?: string; outcomeStatus?: string; evidence?: string; confirmedDate?: string;
  relatedRecordIds?: string; outcomeCount?: number | null; coverage?: string;
  letterSentDate?: string; replyDueDate?: string; replyDate?: string;
  recoveryExpected?: number | null; recoveryActual?: number | null;
  recoveryMethod?: string; recoveryKey?: string; recoveryEntries?: RecoveryEntry[];
  id: string;
  module: string;
  name: string;
  owner: string;
  progressPercent?: number | null;
  tracking?: string;
  previousStageContent?: string;
  previousStageCompletedDate?: string;
  currentStageTask?: string;
  currentStageDueDate?: string;
  progress?: string;
  dueDate: string;
  nextPlan?: string;
  completed: boolean;
  updatedAt: string;
  frozenStatus?: Status;
}
export interface Snapshot {
  schemaVersion?: number;
  id: string;
  week: string;
  savedAt: string;
  asOfDate: string;
  records: AuditRecord[];
}
export interface AuditState {
  teamId?: string;
  schemaVersion: number;
  records: AuditRecord[];
  snapshots: Snapshot[];
}
export interface Envelope {
  revision: number;
  state: AuditState;
}
export interface MergeItem {
  record: AuditRecord;
  existing: AuditRecord | null;
  kind: "new" | "same" | "conflict";
  warning: string;
}
export interface Filters {
  query?: string;
  module?: string;
  status?: string;
  owner?: string;
}
export interface Core {
  people(owner: string): string[];
  normalizePeople(owner: string): string;
  peopleKey(owner: string): string;
  stageOverdue(record: AuditRecord, today?: string): boolean;
  clone<T>(value: T): T;
  id(): string;
  localDate(d?: Date): string;
  monday(date?: string): string;
  validDate(value: string): boolean;
  validTime(value: string): boolean;
  percent(r: AuditRecord): number | null;
  moduleName(m: string): string;
  status(r: AuditRecord, today?: string): Status;
  emptyState(): AuditState;
  validateRecord(value: unknown, options?: { snapshot?: boolean }): string[];
  validateRecords(
    value: unknown,
    options?: { snapshot?: boolean; rowOffset?: number },
  ): string[];
  validateBackup(value: unknown): AuditState;
  recordsFromImport(value: unknown): AuditRecord[];
  sameContent(a: AuditRecord, b: AuditRecord): boolean;
  prepareMerge(current: AuditRecord[], incoming: AuditRecord[]): MergeItem[];
  applyMerge(
    current: AuditRecord[],
    plan: MergeItem[],
    choices?: Record<string, string>,
  ): AuditRecord[];
  snapshot(records: AuditRecord[], week?: string, now?: Date): Snapshot;
  filtered(
    records: AuditRecord[],
    filters: Filters,
    frozen?: boolean,
  ): AuditRecord[];
  stats(
    records: AuditRecord[],
    frozen?: boolean,
  ): {
    total: number;
    normal: number;
    overdue: number;
    completed: number;
    modules: Record<string, number>;
  };
}
export interface ExcelAdapter {
  read(buffer: ArrayBuffer, options?: { teamId?: string }): AuditRecord[];
  workbook(
    records: AuditRecord[],
    options?: { frozen?: boolean; legacy?: boolean; teamId?: string },
  ): unknown;
}
// SheetJS 作为本地脚本加载，业务代码不读取库内部对象。
export interface SheetJSLibrary {
  write(
    wb: unknown,
    options: { type: "array"; bookType: "xlsx"; compression?: boolean },
  ): ArrayBuffer;
}
