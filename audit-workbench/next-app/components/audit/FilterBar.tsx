"use client";
import type { Filters } from "@/types/audit";
import { CONFIG } from "@/lib/audit/utils";
export default function FilterBar({
  filters,
  setFilters,
  modules,
  moduleLabel,
  owners,
  view,
  person,
}: {
  filters: Filters;
  setFilters: (value: Filters) => void;
  modules: { id: string; label: string }[];
  moduleLabel: (id: string) => string;
  owners: string[];
  view: string;
  person: string;
}) {
  return (
    <div className="filter-bar">
      <input
        type="search"
        aria-label="搜索工作"
        placeholder="搜索名称、阶段内容、编号…"
        value={filters.query || ""}
        onChange={(e) => setFilters({ ...filters, query: e.target.value })}
      />
      <select
        aria-label="模块筛选"
        value={filters.module || ""}
        onChange={(e) => setFilters({ ...filters, module: e.target.value })}
      >
        <option value="">全部模块</option>
        {modules.map((m) => (
          <option key={m.id} value={m.id}>
            {moduleLabel(m.id)}
          </option>
        ))}
      </select>
      <select
        aria-label="状态筛选"
        value={filters.status || ""}
        onChange={(e) => setFilters({ ...filters, status: e.target.value })}
      >
        <option value="">全部状态</option>
        {Object.entries(CONFIG.statuses).map(([k, s]) => (
          <option key={k} value={k}>
            {s.label}
          </option>
        ))}
      </select>
      <select
        aria-label="参与人员筛选"
        value={filters.owner || ""}
        disabled={view === "personal"}
        onChange={(e) => setFilters({ ...filters, owner: e.target.value })}
      >
        <option value="">
          {view === "personal" ? person : "全部参与人员"}
        </option>
        {owners.map((o) => (
          <option key={o}>{o}</option>
        ))}
      </select>
      <button onClick={() => setFilters({})}>重置</button>
    </div>
  );
}
