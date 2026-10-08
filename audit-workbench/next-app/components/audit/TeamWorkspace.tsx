"use client";
import { useEffect, useState } from 'react';
import { listTeams, createTeam } from '@/lib/audit/api';
import type { Team } from '@/types/audit';
import AuditWorkspace from './AuditWorkspace';
import '@/styles/audit.css';
export default function TeamWorkspace() {
  const [teams,setTeams] = useState<Team[]>([]), [selected,setSelected] = useState<Team|null>(null);
  const [loading,setLoading] = useState(true), [name,setName] = useState(''), [error,setError] = useState('');
  async function refresh() {
    setLoading(true); setError('');
    try { setTeams(await listTeams()); } catch(e) { setError(e instanceof Error ? e.message : '团队列表读取失败'); }
    finally {setLoading(false);}
  }
  useEffect(() => { void refresh(); }, []);
  if (selected) return <AuditWorkspace key={selected.id} team={selected} onChangeTeam={() => {setSelected(null);void refresh();}}/>;
  return <div className="audit-workspace team-entry"><main>
    <p className="eyebrow">稽核 · 团队工作台</p><h1>选择所属团队</h1>
    <p>先选择团队，再选择填报人。各团队的工作台账、历史周报和成果统计分别保存。</p>
    <p className="muted">团队用于业务分区，可自由选择；不作为访问权限。原有台账位于“原稽核团队”。</p>
    {error && <p role="alert" className="error">{error}</p>}
    {loading ? <p role="status">正在读取团队…</p> : <div className="team-grid">{teams.map(t => <button key={t.id} onClick={() => setSelected(t)}><strong>{t.name}</strong><span>进入团队工作区 →</span></button>)}</div>}
    <button disabled={loading} onClick={() => void refresh()}>刷新团队</button>
    <details><summary>新增团队</summary><form onSubmit={async e => {
      e.preventDefault();setLoading(true);setError('');
      try { const team = await createTeam(name);setTeams(v => [...v,team]);setName('');setSelected(team); }
      catch(e) {setError(e instanceof Error ? e.message : '创建失败，请刷新检查');}
      finally {setLoading(false);}
    }}><label>团队名称<input aria-label="新增团队名称" required maxLength={60} value={name} onChange={e=>setName(e.target.value)}/></label><button className="primary" disabled={loading}>创建并进入</button></form></details>
  </main></div>;
}
