"use client";
import { useEffect, useState, useRef } from "react";
import { CONFIG, K } from "@/lib/audit/utils";
import { loadWorkspace, saveWorkspace, dataMode, bindTeam } from "@/lib/audit/api";
import { download, exportExcel } from "@/lib/audit/excel";
import { $static } from "@/util/public";
import type {
  AuditState,
  AuditRecord,
  Envelope,
  MergeItem,
  Filters,
  Team,
  Status,
} from "@/types/audit";
import RecordEditor from "./AuditForm";
import AuditDetail from "./AuditDetail";
import AuditTable from "./AuditTable";
import FilterBar from "./FilterBar";
import "@/styles/audit.css";
import ImportDialog from "./ExcelOperations";
import BackupDialog, { backupText } from "./BackupDialog";
import Modal from "./Modal";
import HelpDialog from "./HelpDialog";
import { retainHistory, setArchived } from "@/lib/domain/enhancements.js";
import { RecoverySummary, ManagerFocus, WeeklyChanges, OutcomeLine } from "./Insights";
import { OverdueAging, HistoryTrend } from "./Trends";
type Panel =
  | "editor"
  | "import"
  | "backup"
  | "person"
  | "snapshot"
  | "detail"
  | "help"
  | "clear"
  | null;
const errText = (e: unknown) =>
  e instanceof Error ? e.message : "操作失败，请重试";
export default function AuditWorkspace({team,onChangeTeam}: {team:Team;onChangeTeam:()=>void}) {
  const [env, setEnv] = useState<Envelope | null>(null),
    [busy, setBusy] = useState(false),
    [loading, setLoading] = useState(true);
  const [error, setError] = useState(""),
    [message, setMessage] = useState(""),
    [panel, setPanel] = useState<Panel>(null);
  const [view, setView] = useState<"department" | "personal" | "history" | "archive">(
      "department",
    ),
    [person, setPerson] = useState(""),
    [personDraft, setPersonDraft] = useState("");
  const [layout, setLayout] = useState<"list" | "cards">("list"),
    [filters, setFilters] = useState<Filters>({}),
    [sort, setSort] = useState("priority");
  const [edit, setEdit] = useState<AuditRecord | undefined>(),
    [detail, setDetail] = useState<AuditRecord | null>(null);
  const [selected, setSelected] = useState(""),
    [week, setWeek] = useState(""),
    [today, setToday] = useState("");
  const [pending, setPending] = useState<{
      state: AuditState;
      revision: number;
    } | null>(null),
    [pendingDownloaded, setPendingDownloaded] = useState(false);
  const [noteDrafts,setNoteDrafts] = useState<Record<string,string>>({});
  const hasNoteDrafts = Object.keys(noteDrafts).length>0;
  useEffect(()=>{
    const handler=(e:BeforeUnloadEvent)=>{if(hasNoteDrafts){e.preventDefault();e.returnValue='';}};
    window.addEventListener('beforeunload',handler);
    return ()=>window.removeEventListener('beforeunload',handler);
  },[hasNoteDrafts]);
  useEffect(()=>{if(env) setNoteDrafts(previous=>Object.fromEntries(Object.entries(previous).filter(([id,value])=>value!==(env.state.records.find(r=>r.id===id)?.remarks||''))));},[env]);
  const [clearAck,setClearAck] = useState(false);
  const listRef = useRef<HTMLElement>(null);
  const loadSequence = useRef(0),
    lock = useRef(false);
  async function refresh(discardNotes=false) {
    if(hasNoteDrafts && !discardNotes){setError("请先保存或取消未保存的备注，再刷新台账。");return;}
    const seq = ++loadSequence.current;
    setLoading(true);
    setError("");
    try {
      const data = await loadWorkspace(team.id);
      if (seq === loadSequence.current) {
        setEnv(data);
        setMessage("台账已刷新");
      }
    } catch (e) {
      if (seq === loadSequence.current) setError(errText(e));
    } finally {
      if (seq === loadSequence.current) setLoading(false);
    }
  }
  useEffect(() => {
    void refresh();
    setToday(K.localDate());
    try {
      setPerson(localStorage.getItem(`audit-mini-app.person.${team.id}`) || (team.id === "default" ? localStorage.getItem("audit-mini-app.person") : "") || "");
    } catch {}
    const timer = setInterval(() => setToday(K.localDate()), 30000);
    return () => {
      clearInterval(timer);
      loadSequence.current++;
    };
  }, []);
  const state = env?.state || K.emptyState();
  const snapshot = state.snapshots.find((s) => s.id === selected);
  const frozen = view === "history";
  const archiveView = view === "archive";
  const activeRecords = state.records.filter(r=>!r.archivedAt);
  const archivedRecords = state.records.filter(r=>!!r.archivedAt);
  const source = frozen
    ? (snapshot?.records || []).filter(r=>!r.archivedAt)
    : archiveView ? archivedRecords
    : view === "personal"
      ? activeRecords.filter((r) => K.people(r.owner).includes(person))
      : activeRecords;
  // 工作清单不含归档；累计贡献仍计入归档成果，避免归档使团队贡献减少。
  const recoveryRecords = K.filtered(frozen ? snapshot?.records || [] : archiveView ? archivedRecords : state.records,
    {...filters, owner:view==='personal' ? person : filters.owner}, frozen);
  const visible = K.filtered(
    source,
    { ...filters, owner: view === "personal" ? person : filters.owner },
    frozen,
  ).sort((a, b) => {
    if (sort === "updated") return b.updatedAt.localeCompare(a.updatedAt);
    if (sort === "priority") {
      const ranks = { overdue: 0, normal: 1, completed: 2 };
      const diff =
        ranks[frozen ? a.frozenStatus! : K.status(a)] -
        ranks[frozen ? b.frozenStatus! : K.status(b)];
      if (diff) return diff;
    }
    return (
      a.dueDate.localeCompare(b.dueDate) ||
      a.name.localeCompare(b.name, "zh-CN")
    );
  });
  const modules = [
    ...CONFIG.modules,
    ...(source.some((r) => r.module === "promotion")
      ? CONFIG.legacyModules
      : []),
  ];
  const moduleLabel = (id: string) =>
    frozen && snapshot?.schemaVersion === 1
      ? id === "project"
        ? "项目"
        : id === "promotion"
          ? "三促／三函／挽损"
          : K.moduleName(id)
      : K.moduleName(id);
  const stats = K.stats(visible, frozen),
    disabled = busy || loading || !env || !!pending;
  const owners = Array.from(
    new Set(source.flatMap((r) => K.people(r.owner))),
  ).sort((a, b) => a.localeCompare(b, "zh-CN"));
  function close() {
    if (!busy) {
      setPanel(null);
      setError("");
    }
  }
  function open(which: Panel) {
    if(hasNoteDrafts && which!=="detail" && which!=="help"){setError("请先保存或取消未保存的备注，再进行此操作。");return;}
    setError("");
    setMessage("");
    setPanel(which);
  }
  function switchView(next: typeof view) {
    setView(next);
    setFilters({});
    if (next === "history") setSelected(state.snapshots.at(-1)?.id || "");
  }
  async function commit(
    candidate: AuditState,
    success: string,
    options?: { retry?: boolean },
  ) {
    if (!env || lock.current || (pending && !options?.retry)) return false;
    try {
      candidate = bindTeam(candidate, team.id);
      K.validateBackup(candidate);
    } catch (e) {
      setError(errText(e));
      return false;
    }
    lock.current = true;
    setBusy(true);
    setError("");
    const revision =
      options?.retry && pending ? pending.revision : env.revision;
    try {
      const result = await saveWorkspace(candidate, revision, team.id);
      setEnv(result);
      setPending(null);
      setPendingDownloaded(false);
      setMessage(success);
      return true;
    } catch (e) {
      setPending({ state: K.clone(candidate), revision });
      setPendingDownloaded(false);
      setError(errText(e));
      return false;
    } finally {
      lock.current = false;
      setBusy(false);
    }
  }
  async function writeRecord(record: AuditRecord) {
    if (state.records.find(r=>r.id===record.id)?.archivedAt) {setError('请先从归档栏恢复到工作清单，再更新进展');return;}
    record = {...record,teamId:team.id};
    record = retainHistory(state.records.find(r=>r.id===record.id), record, K.id);
    if (
      state.records.some(
        (r) =>
          r.id !== record.id &&
          r.module === record.module &&
          r.name === record.name &&
          K.peopleKey(r.owner) === K.peopleKey(record.owner),
      ) &&
      !confirm("已有同模块、同名称、同参与人员的记录，确认这是另一项工作？")
    )
      return;
    const next = K.clone(state),
      index = next.records.findIndex((r) => r.id === record.id);
    if (index < 0) next.records.push(record);
    else next.records[index] = record;
    if (await commit(next, edit ? "工作已更新" : "工作已新增")) setPanel(null);
  }
  function changeNote(record:AuditRecord,value:string) {
    setNoteDrafts(previous=>{const next={...previous};if(value===(record.remarks||'')) delete next[record.id];else next[record.id]=value;return next;});
  }
  function cancelNote(id:string) {setNoteDrafts(previous=>{const next={...previous};delete next[id];return next;});}
  async function saveNote(record:AuditRecord) {
    if(disabled || noteDrafts[record.id]===undefined) return;
    const current=state.records.find(r=>r.id===record.id);
    if(!current || current.archivedAt || frozen) return;
    const value=noteDrafts[record.id], next=K.clone(state);
    next.records=next.records.map(r=>r.id===current.id?{...r,remarks:value,updatedAt:new Date().toISOString()}:r);
    if(await commit(next,'备注已保存')) cancelNote(record.id);
  }
  async function removeRecord(record: AuditRecord) {
    const next = K.clone(state);
    next.records = next.records.filter((r) => r.id !== record.id);
    if (await commit(next, "工作已删除，历史周报保持不变")) setPanel(null);
  }
  async function archiveRecord(record: AuditRecord) {
    if (disabled || frozen) return;
    const current=state.records.find(r=>r.id===record.id);
    if (!current) return;
    try {
      const next=K.clone(state), archived=!current.archivedAt;
      next.records=next.records.map(r=>r.id===current.id ? setArchived(r,archived) : r);
      await commit(next, archived ? '工作已归档，可在历史周报下方的归档栏查看' : '已恢复到工作清单，完成状态和历史内容保持不变');
    } catch(e) {setError(errText(e));}
  }
  async function applyImport(
    plan: MergeItem[],
    choices: Record<string, string>,
  ) {
    try {
      const next = K.clone(state);
      next.records = K.applyMerge(state.records, plan, choices);
      const n = plan.filter((p) => p.kind === "new").length,
        u = plan.filter(
          (p) => p.kind === "conflict" && choices[p.record.id] === "incoming",
        ).length,
        s = plan.filter((p) => p.kind === "same").length,
        c = plan.length - n - u - s;
      if (
        await commit(
          next,
          `汇总完成：新增 ${n}、更新 ${u}、保留 ${c}、跳过 ${s} 项`,
        )
      )
        setPanel(null);
    } catch (e) {
      setError(errText(e));
    }
  }
  async function xlsx(records: AuditRecord[], name: string, history = false) {
    setError("");
    try {
      await exportExcel(
        records,
        name,
        history,
        history && snapshot?.schemaVersion === 1,
        team.id,
      );
      setMessage("已发起 Excel 下载，请确认文件保存完成");
    } catch (e) {
      setError(errText(e));
    }
  }
  function newRecord() {
    setEdit(undefined);
    open("editor");
  }
  function badge(r: AuditRecord) {
    const status = frozen ? r.frozenStatus! : K.status(r);
    return (
      <span><span className={`badge ${status}`}>{CONFIG.statuses[status].label}</span>{status==='overdue' && <small className="overdue-rule">未完成，且整体交付日期早于{frozen?`留档基准日 ${snapshot?.asOfDate}`:"今天"}；当天到期不算逾期</small>}</span>
    );
  }
  function progress(r: AuditRecord) {
    const pct = K.percent(r);
    return (
      <div className="progress-cell">
        <strong>{pct === null ? "未填写" : `${pct}%`}</strong>
        {pct !== null && (
          <progress aria-label={`${r.name}进度`} value={pct} max={100} />
        )}
      </div>
    );
  }
  return (
    <div className="audit-workspace">
      <aside className="sidebar">
        <div className="brand">
          <span>稽</span>
          <div>
            稽核进度看板<small>团队工作台 · 演示版</small>
          </div>
        </div>
        <div className="team-current"><small>所属团队</small><strong>{team.name}</strong><button disabled={busy || loading || !!pending || !!panel || hasNoteDrafts} onClick={onChangeTeam}>切换团队</button></div>
        <p className="nav-caption">日常工作</p>
        <button
          className={view === "department" ? "active" : ""}
          onClick={() => switchView("department")}
        >
          ▦ 部门看板
        </button>
        <button
          className={view === "personal" ? "active" : ""}
          onClick={() => {
            if (person) switchView("personal");
            else {
              setPersonDraft("");
              open("person");
            }
          }}
        >
          ◎ 我的工作
        </button>
        <button
          className={view === "history" ? "active" : ""}
          onClick={() => switchView("history")}
        >
          ◷ 历史周报 <span>{state.snapshots.length}</span>
        </button>
        <button className={archiveView ? 'active' : ''} onClick={()=>switchView('archive')}>
          ▣ 归档 <span>{archivedRecords.length}</span>
        </button>
        <p className="nav-caption">七类工作</p>
        {modules.map((m) => (
          <button
            key={m.id}
            className={filters.module === m.id ? "active" : ""}
            onClick={() => setFilters({ ...filters, module: m.id })}
          >
            {moduleLabel(m.id)}
            <span>{stats.modules[m.id]}</span>
          </button>
        ))}
        <div className="sidebar-bottom">
          <button
            disabled={!env || busy || loading || !!pending}
            onClick={() => open("backup")}
          >
            备份与恢复
          </button>
          <button className="help-entry" aria-haspopup="dialog" onClick={() => open("help")}><span className="help-entry-icon" aria-hidden="true">?</span><strong>使用说明</strong><small>按标签查看操作方法</small></button>
          <p>
            {dataMode === "platform"
              ? "公司轻应用 · 部门台账"
              : "本机数据库 · 参考运行"}
            <small>保存结果以页面提示为准</small>
          </p>
        </div>
      </aside>
      <main>
        <div className="topline">
          <span>
            {team.name} /{" "}
            {archiveView ? "归档" : view === "personal"
              ? "我的工作"
              : frozen
                ? "历史周报"
                : "部门看板"}
          </span>
          <span>{today}</span>
        </div>
        <header className="page-heading">
          <div>
            <p className="eyebrow">{team.name} · 工作管理</p>
            <h1>
              {archiveView ? "已完成工作归档" : view === "personal"
                ? "我的工作"
                : frozen
                  ? "历史周报"
                  : CONFIG.appName}
            </h1>
            <p className="muted">
              {archiveView ? "集中查看已归档事项；可查看完整内容、筛选导出，或恢复到工作清单。" : frozen
                ? "查看留档时的进度和状态，历史版本仅供阅读。"
                : view === "personal"
                  ? `填报人：${person} · 更新进展，必要时下载个人工作表交接。`
                  : "汇总七类工作，查看进度、交付日期和下一步安排。"}
            </p>
          </div>
          {!frozen && !archiveView && (
            <button className="primary" disabled={disabled} onClick={newRecord}>
              ＋ 新增工作
            </button>
          )}
        </header>
        {error && (
          <p className="error" role="alert">
            {error}
          </p>
        )}
        {message && (
          <p className="message" role="status">
            {message}
          </p>
        )}
        {pending && (
          <section className="error">
            <strong>本次保存没有确认成功，待保存副本仍保留在当前页面。</strong>
            <p>
              先下载副本。若其他人已更新台账，请下载后刷新，再用普通合并逐条核对，不直接覆盖。
            </p>
            <div className="actions">
              <button
                onClick={() => {
                  download(
                    backupText(pending.state),
                    `待保存工作_${Date.now()}.json`,
                  );
                  setPendingDownloaded(true);
                }}
              >
                下载待保存备份
              </button>
              <button
                disabled={busy}
                onClick={() =>
                  void commit(pending.state, "已重新保存", { retry: true })
                }
              >
                重试原版本保存
              </button>
              <button
                disabled={!pendingDownloaded || busy}
                onClick={() => {
                  if (
                    confirm(
                      "确认待保存文件已下载完成？将放弃本次页面候选并刷新。",
                    )
                  ) {
                    setPanel(null);
                    setPending(null);
                    setNoteDrafts({});
                    void refresh(true);
                  }
                }}
              >
                下载后放弃本次保存并刷新
              </button>
            </div>
          </section>
        )}
        {!env && (
          <section className="empty-state">
            <h2>{loading ? "正在读取台账…" : "暂时无法读取台账"}</h2>
            <p>连接成功前不会显示保存成功，也不会改用浏览器台账。</p>
            <button disabled={loading} onClick={() => void refresh()}>
              重新读取
            </button>
          </section>
        )}
        {env && (
          <>
            {hasNoteDrafts && <div className="notice" role="status">有 {Object.keys(noteDrafts).length} 条备注尚未保存。<button onClick={()=>{setView('department');setFilters({});listRef.current?.scrollIntoView({block:'start'});}}>返回备注所在清单</button></div>}
            {view === "personal" && (
              <div className="personal-strip">
                <span>姓名用于快速筛选，不是账号权限。</span>
                <button
                  onClick={() => {
                    setPersonDraft(person);
                    open("person");
                  }}
                >
                  更换姓名
                </button>
                <button
                  disabled={disabled}
                  onClick={() => void xlsx([], "稽核填写模板")}
                >
                  下载空白填写表
                </button>
              </div>
            )}
            {frozen && (
              <section className="history-panel">
                <label>
                  选择留档版本
                  <select
                    aria-label="选择留档版本"
                    value={selected}
                    onChange={(e) => setSelected(e.target.value)}
                  >
                    <option value="">请选择周报</option>
                    {state.snapshots
                      .slice()
                      .reverse()
                      .map((s) => (
                        <option key={s.id} value={s.id}>
                          {s.week} 所属周 ·{" "}
                          {new Date(s.savedAt).toLocaleString("zh-CN")} ·{" "}
                          {s.records.filter(r=>!r.archivedAt).length} 项（未归档）
                        </option>
                      ))}
                  </select>
                </label>
                <p>
                  {snapshot
                    ? `状态基准日 ${snapshot.asOfDate}，本次留档保持当时的数据。`
                    : "暂无选中版本，请选择已有周报或返回当前台账留档。"}
                </p>
                <button
                  disabled={!snapshot || disabled}
                  className="danger"
                  onClick={async () => {
                    if (
                      snapshot &&
                      confirm("确认删除该历史版本？请先保存完整备份。")
                    ) {
                      const next = K.clone(state);
                      next.snapshots = next.snapshots.filter(
                        (s) => s.id !== snapshot.id,
                      );
                      if (await commit(next, "历史版本已删除")) setSelected("");
                    }
                  }}
                >
                  删除此周报
                </button>
              </section>
            )}
            <div className="scope-strip"><span>当前范围：{team.name} · {filters.module?moduleLabel(filters.module):'全部模块'} · {view==='personal'?person:filters.owner||'全部人员'} · {filters.status?CONFIG.statuses[filters.status as Status]?.label:'全部状态'}{filters.query?` · 搜索“${filters.query}”`:''}</span><button onClick={()=>setFilters({})}>清除全部筛选</button></div>
            <section className="stats" aria-label="统计概览">
              {[
                { key: "total", label: "工作总数" },
                { key: "overdue", label: "已逾期" },
                { key: "normal", label: "未逾期" },
                { key: "completed", label: "已完成" },
              ].map((item) => (
                <button
                  key={item.key}
                  data-testid={`stat-${item.key}`}
                  className={`stat ${item.key}`}
                  aria-pressed={(filters.status || "") === (item.key === "total" ? "" : item.key)}
                  onClick={() => {
                    setFilters({...filters,status:item.key === "total" ? "" : item.key});
                    listRef.current?.scrollIntoView({block:"start"});
                    listRef.current?.focus({preventScroll:true});
                  }}
                >
                  <span>{item.label}</span>
                  <strong>
                    {
                      stats[
                        item.key as "total" | "normal" | "overdue" | "completed"
                      ]
                    }
                    <small>项</small>
                  </strong>
                  <span>当前筛选范围</span>{item.key==='overdue' && <small className="overdue-rule">未完成，且整体交付日期早于{frozen?'留档基准日':'今天'}；当天到期不算逾期</small>}
                </button>
              ))}
            </section>
            {!frozen && view === "department" && <>
              <ManagerFocus records={visible} today={today} onDetail={r=>{setDetail(r);open("detail");}}/>
              <OverdueAging records={visible} today={today} onDetail={r=>{setDetail(r);open("detail");}}/>
              <HistoryTrend snapshots={state.snapshots} onSelect={id=>{switchView("history");setSelected(id);}}/>
              <WeeklyChanges state={state} onDetail={r=>{setDetail(r);open("detail");}}/>
            </>}
            {(!filters.module || filters.module === "loss-recovery") && <RecoverySummary records={recoveryRecords} includesArchived={!archiveView}/>}
            <section className="workspace" ref={listRef} tabIndex={-1} aria-label="工作台账列表">
              <div className="section-heading">
                <div>
                  <h2>{frozen ? "已留档工作" : archiveView ? "归档清单" : "工作台账"}</h2>
                  <span className="muted">显示 {visible.length} 项</span>
                </div>
                <div className="tools">
                  <button
                    disabled={busy || loading || !!panel}
                    onClick={() => void refresh()}
                  >
                    刷新台账
                  </button>
                  {!frozen && !archiveView && (
                    <button disabled={disabled} onClick={() => open("import")}>
                      汇总同事进展
                    </button>
                  )}
                  {view === "personal" && (
                    <button
                      className="primary"
                      disabled={disabled || !source.length}
                      onClick={() =>
                        void xlsx(
                          source,
                          `工作进展_${person.replace(/[\\/:*?"<>|]/g, "_")}`,
                        )
                      }
                    >
                      下载我的提交文件
                    </button>
                  )}
                  {view === "department" && (
                    <button
                      disabled={disabled}
                      onClick={() => {
                        setWeek(K.monday());
                        open("snapshot");
                      }}
                    >
                      本周留档
                    </button>
                  )}
                  <button
                    disabled={busy || !visible.length}
                    onClick={() =>
                      void xlsx(
                        visible,
                        frozen ? "稽核历史周报" : archiveView ? "稽核归档清单" : "稽核当前列表",
                        frozen,
                      )
                    }
                  >
                    下载当前列表
                  </button>
                  <button
                    disabled={busy || !state.records.length}
                    onClick={() => void xlsx(state.records, "稽核全部台账")}
                  >
                    导出全部台账（含归档）
                  </button>
                  {!frozen && (
                    <button
                      className="danger"
                      disabled={
                        disabled ||
                        (!state.records.length && !state.snapshots.length)
                      }
                      onClick={() => {setClearAck(false);open("clear");}}
                    >
                      系统清空
                    </button>
                  )}
                </div>
              </div>
              <FilterBar
                filters={filters}
                setFilters={setFilters}
                modules={modules}
                moduleLabel={moduleLabel}
                owners={owners}
                view={view}
                person={person}
              />
              <div className="view-toolbar">
                <span>统计随筛选变化 · 点击工作名称查看完整内容</span>
                <div>
                  <select
                    aria-label="排序"
                    value={sort}
                    onChange={(e) => setSort(e.target.value)}
                  >
                    <option value="priority">逾期优先</option>
                    <option value="due">交付日期</option>
                    <option value="updated">最近更新</option>
                  </select>
                  <button
                    aria-pressed={layout === "list"}
                    onClick={() => setLayout("list")}
                  >
                    列表
                  </button>
                  <button
                    aria-pressed={layout === "cards"}
                    onClick={() => setLayout("cards")}
                  >
                    卡片
                  </button>
                </div>
              </div>
              {!frozen &&
                source.some((r) => r.module === "promotion") && (
                  <p className="notice">
                    有{" "}
                    {
                      source.filter((r) => r.module === "promotion")
                        .length
                    }{" "}
                    项旧“三促／三函／挽损”工作待归类。请在下方待归类区点击“更新进展”，选择新模块；编号和内容保持不变。
                  </p>
                )}
              {stats.overdue > 0 && (
                <p className="notice">
                  {frozen ? "留档时" : "当前筛选中"}有 {stats.overdue}{" "}
                  项已逾期，请结合进展和下一步安排跟进。
                </p>
              )}
              {!visible.length && (
                <div className="empty-state">
                  <h3>{archiveView ? '暂无可显示的归档事项' : '暂无可显示的工作'}</h3>
                  <p>{archiveView ? '可调整筛选条件；在日常工作清单中，将已完成事项归档后会显示在这里。' : '调整筛选条件，或新增、汇总工作记录。'}</p>
                </div>
              )}
              {modules
                .filter((m) => !filters.module || filters.module === m.id)
                .map((m) => {
                  const records = visible.filter((r) => r.module === m.id);
                  if (!records.length) return null;
                  return (
                    <section key={m.id} className="module-section">
                      <h3>
                        <span className="module-number">
                          {String(modules.indexOf(m) + 1).padStart(2, "0")}
                        </span>
                        {moduleLabel(m.id)}
                        <small>{records.length} 项</small>
                      </h3>
                      {records.some(r=>r.outcomeSummary || r.outcomeStatus || r.outcomeCount!=null || r.module==='loss-recovery') && <details className="module-outcomes"><summary>查看本模块成果</summary>{records.map(r=><article key={r.id}><button onClick={()=>{setDetail(r);open('detail');}}>{r.name}</button><OutcomeLine record={r}/></article>)}</details>}
                      <AuditTable
                        records={records}
                        noteDrafts={noteDrafts}
                        onNoteChange={changeNote}
                        onNoteSave={r=>void saveNote(r)}
                        onNoteCancel={cancelNote}
                        layout={layout}
                        frozen={frozen}
                        disabled={disabled}
                        legacy={frozen && snapshot?.schemaVersion === 1}
                        asOfDate={frozen ? snapshot?.asOfDate : today}
                        progress={progress}
                        badge={badge}
                        onDetail={(r) => {
                          setDetail(r);
                          open("detail");
                        }}
                        onEdit={(r) => {
                          setEdit(r);
                          open("editor");
                        }}
                        onArchive={r=>void archiveRecord(r)}
                      />
                    </section>
                  );
                })}
            </section>
            <footer>
              部门台账版本 {env.revision} ·{" "}
              {busy ? "保存中…" : "以成功提示确认保存"}
              <span>当天到期不算逾期 · 历史状态以留档日为准</span>
            </footer>
          </>
        )}
      </main>
      {panel === "clear" && <Modal title="清空当前团队" onClose={close} busy={busy} error={error}>
        <p>将清空“{team.name}”的 {state.records.length} 项工作及 {state.snapshots.length} 份周快照。其他团队不受影响。</p>
        <p>此操作不能撤销，请先下载包含全部历史的 JSON 备份。</p>
        <button onClick={()=>download(backupText(state),`清空前备份_${team.name}_${Date.now()}.json`)}>下载清空前备份</button>
        <label className="check"><input type="checkbox" aria-label="确认清空当前团队" checked={clearAck} onChange={e=>setClearAck(e.target.checked)}/>已核对团队并了解清空范围</label>
        <div className="actions"><button onClick={close} disabled={busy}>取消清空</button><button className="danger" disabled={!clearAck||busy} onClick={async()=>{if(await commit(K.emptyState(),"当前团队已清空，其他团队不受影响"))close();}}>确认清空</button></div>
      </Modal>}
      {panel === "editor" && (
        <RecordEditor
          record={edit}
          records={state.records}
          owner={person}
          onClose={close}
          onSave={writeRecord}
          onDelete={removeRecord}
          busy={busy}
          error={error}
        />
      )}
      {panel === "import" && (
        <ImportDialog
          current={state.records}
          teamId={team.id}
          onClose={close}
          onApply={applyImport}
          busy={busy}
          error={error}
        />
      )}
      {panel === "backup" && (
        <BackupDialog
          current={state}
          onClose={close}
          onRestore={async (next) => {
            if (await commit(next, "完整恢复成功")) {
              setSelected("");
              setView("department");
              setPanel(null);
            }
          }}
          busy={busy}
          error={error}
        />
      )}
      {panel === "person" && (
        <Modal title="选择填报人" onClose={close}>
          <form
            onSubmit={(e) => {
              e.preventDefault();
              const name = personDraft.trim();
              if (!name) return;
              setPerson(name);
              try {
                localStorage.setItem(`audit-mini-app.person.${team.id}`, name);
              } catch {}
              switchView("personal");
              close();
            }}
          >
            <label>
              所属团队：{team.name}<br/>负责人姓名
              <input
                aria-label="填报人姓名"
                required
                maxLength={100}
                value={personDraft}
                onChange={(e) => setPersonDraft(e.target.value)}
              />
            </label>
            <p className="muted">
              与台账姓名一致，用于筛选，不替代公司登录权限。
            </p>
            <div className="actions">
              <button className="primary">确定</button>
            </div>
          </form>
        </Modal>
      )}
      {panel === "snapshot" && (
        <Modal title="本周工作留档" onClose={close} busy={busy} error={error}>
          <form
            onSubmit={async (e) => {
              e.preventDefault();
              try {
                const next = K.clone(state);
                next.snapshots.push(K.snapshot(state.records, week));
                if (
                  await commit(next, "本周留档已保存，建议立即下载完整备份")
                ) {
                  setPanel(null);
                }
              } catch (e) {
                setError(errText(e));
              }
            }}
          >
            <p>
              保存全部门当前台账和当时状态，不受筛选影响。同一周可留多个版本。
            </p>
            <label>
              所属周（周一）
              <input
                aria-label="所属周"
                type="date"
                required
                value={week}
                onChange={(e) => setWeek(e.target.value)}
              />
            </label>
            <p className="muted">
              所属周是标签，选择旧周不会自动恢复过去的台账。
            </p>
            <div className="actions">
              <button className="primary" disabled={busy}>
                确认留档
              </button>
            </div>
          </form>
        </Modal>
      )}
      {panel === "detail" && detail && (
        <AuditDetail
          record={detail}
          records={frozen ? snapshot?.records || [] : state.records}
          frozen={frozen}
          legacy={frozen && snapshot?.schemaVersion === 1}
          asOfDate={frozen ? snapshot?.asOfDate : today}
          onClose={close}
          onRelated={setDetail}
          onEdit={
            disabled || frozen || !!detail.archivedAt || !state.records.some(r=>r.id===detail.id)
              ? undefined
              : () => {
                  setEdit(detail);
                  open("editor");
                }
          }
        />
      )}
      {panel === "help" && <HelpDialog onClose={close}/>}
    </div>
  );
}
