"use client";
import type {AuditRecord} from '@/types/audit';
import {collaborationStatuses} from '@/lib/domain/enhancements.js';
export default function CollaborationFields({draft,onChange}:{draft:AuditRecord;onChange:(key:'collaborationStatus'|'followUpDate',value:string)=>void}) {
  return <><label>协作状态<select aria-label="协作状态" value={draft.collaborationStatus||''} onChange={e=>onChange('collaborationStatus',e.target.value)}><option value="">未填写</option>{collaborationStatuses.map(v=><option key={v}>{v}</option>)}</select></label>
    <label>跟进日期<input aria-label="跟进日期" type="date" value={draft.followUpDate||''} onChange={e=>onChange('followUpDate',e.target.value)}/></label></>;
}
