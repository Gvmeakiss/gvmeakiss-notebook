"use client";
import Modal from './Modal';
import {helpSections,helpUpdatedAt} from '@/lib/domain/help-content.js';
import {$static} from '@/util/public';
export default function HelpDialog({onClose}:{onClose:()=>void}) {
  return <Modal title="使用说明" onClose={onClose}>
    <p className="muted">按标签查找，点击展开；再次点击收起。更新于 {helpUpdatedAt}。</p>
    <div className="help-sections">{helpSections.map(section=><details className="help-section" key={section.id}>
      <summary><span className="help-tag">{section.tag}</span><span className="help-caption">{section.title}</span></summary>
      <div className="help-body">{section.paragraphs.map((paragraph,index)=><p key={index}>{paragraph}</p>)}</div>
    </details>)}</div>
    <div className="help-links"><a href={$static('/使用说明.html')} target="_blank" rel="noopener">独立打开使用说明</a><a href={$static('/demo/fictional-audit.xlsx')} download>下载虚构演示 Excel</a></div>
    <p className="muted">演示文件需手动导入，不会自动写入台账。</p>
  </Modal>;
}
