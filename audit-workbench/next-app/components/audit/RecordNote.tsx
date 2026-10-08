"use client";
import type {AuditRecord} from '@/types/audit';
export default function RecordNote({record,draft,readOnly,disabled,onChange,onSave,onCancel}:{record:AuditRecord;draft?:string;readOnly:boolean;disabled:boolean;onChange:(value:string)=>void;onSave:()=>void;onCancel:()=>void}) {
  if(readOnly) return <p className="record-remark">备注：{record.remarks||'—'}</p>;
  return <div className="record-remark"><label>备注<textarea aria-label={`备注 ${record.name}`} rows={1} maxLength={2000} placeholder="点击填写备注" value={draft??record.remarks??''} disabled={disabled} onChange={e=>onChange(e.target.value)}/></label>
    {draft!==undefined && <div className="note-actions"><small>未保存</small><button disabled={disabled} onClick={onSave}>保存备注</button><button disabled={disabled} onClick={onCancel}>取消备注</button></div>}
  </div>;
}
