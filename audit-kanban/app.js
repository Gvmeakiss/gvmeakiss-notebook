/* 页面协调层：所有台账修改经过 commit()，先持久化成功，再更新界面。
 * 导入、恢复先在内存中预览，不提前写入 localStorage。
 */
(function () {
  'use strict';
  const C = window.CONFIG, K = window.KanbanCore, E = window.KanbanExcel;
  const $ = id => document.getElementById(id);
  const stateKey = C.storageKey;
  let state = K.emptyState(), loadedRaw = null, storageBroken = false, pendingState = null;
  let selectedSnapshot = '', historyOpen = false, editingId = null, mergePlan = [], mergeBase = null;
  let restoreCandidate = null, restoreBase = null, backupText = null, backupVerified = false;
  let importSequence = 0, restoreSequence = 0;
  // 仅用于方便填写，不是登录身份或权限。偏好与业务台账分开保存。
  let personalView = false, personName = '', personAction = 'view', detailRecord = null;
  let displayMode = C.ui.defaultView;
  const preferencesKey = `${stateKey}.preferences`;
  try {
    const prefs = JSON.parse(localStorage.getItem(preferencesKey) || '{}');
    if (typeof prefs.personName === 'string') personName = prefs.personName.slice(0, 100);
    if (['list', 'cards'].includes(prefs.displayMode)) displayMode = prefs.displayMode;
  } catch (_) { /* 偏好不可用时仍可正常使用台账。 */ }
  function savePreferences() {
    try { localStorage.setItem(preferencesKey, JSON.stringify({ personName, displayMode })); }
    catch (_) { message('已在本次使用中记住选择；下次打开可能需要重新选择姓名。'); }
  }
  function el(tag, text, className) {
    const node = document.createElement(tag);
    if (text !== undefined) node.textContent = text;
    if (className) node.className = className;
    return node;
  }
  function button(text, handler, className) { const b = el('button', text, className); b.type = 'button'; b.addEventListener('click', handler); return b; }
  function option(value, label) { const node = el('option', label); node.value = value; return node; }
  function errorAt(id, error) { $(id).textContent = error ? String(error.message || error) : ''; $(id).hidden = !error; }
  function message(text, error = false) { $('message').textContent = text; $('message').className = error ? 'error' : ''; $('message').hidden = false; }
  function show(id) { $(id).showModal(); }
  function close(id) { $(id).close(); }
  function stamp(value) { return new Date(value).toLocaleString('zh-CN', { hour12: false }); }
  function storageWarning(text) {
    $('storage-message').textContent = text;
    $('storage-warning').hidden = false;
    $('retry-save').disabled = !pendingState || storageBroken;
    $('emergency-export').disabled = !pendingState && storageBroken;
    $('raw-export').disabled = loadedRaw === null;
  }
  function initialize() {
    try {
      loadedRaw = localStorage.getItem(stateKey);
      if (loadedRaw !== null) state = K.validateBackup(JSON.parse(loadedRaw));
      const probe = `${stateKey}.probe.${K.id()}`;
      localStorage.setItem(probe, '1');
      localStorage.removeItem(probe);
      $('save-status').textContent = '已启用本机自动保存';
    } catch (error) {
      // 非空但无法解析时保留原文并锁定编辑，不能用空台账覆盖损坏的数据。
      try { if (loadedRaw !== null) K.validateBackup(JSON.parse(loadedRaw)); }
      catch (_) { storageBroken = true; }
      storageWarning(`本机存储不可用或原数据无法读取：${error.message}。请导出原始数据；可从完整备份恢复。`);
      $('save-status').textContent = '存储异常 · 请先备份';
    }
  }
  function commit(candidate, successText, options = {}) {
    let validated;
    try { validated = K.validateBackup(candidate); }
    catch (error) { message(error.message, true); return false; }
    try {
      if (storageBroken && !options.restore) throw new Error('原始数据无法读取，请先导出原始存储并从备份恢复');
      if (pendingState && !options.retry && !options.restore) throw new Error('还有一次写入失败的数据，请先重试保存，或导出待保存数据后刷新');
      const currentRaw = localStorage.getItem(stateKey);
      if (currentRaw !== loadedRaw) throw new Error('数据已被另一个页面修改。请导出待保存数据后刷新，再通过导入合并处理');
      const raw = JSON.stringify(validated);
      localStorage.setItem(stateKey, raw);
      state = validated; loadedRaw = raw; storageBroken = false; pendingState = null;
      $('storage-warning').hidden = true;
      $('save-status').textContent = `已保存到本机 · ${new Date().toLocaleTimeString('zh-CN', { hour12: false })}`;
      render(); message(successText); return true;
    } catch (error) {
      // 保留首次失败的完整候选，禁止后续操作把它静默替换掉。
      if (!pendingState && !storageBroken) pendingState = K.clone(candidate);
      storageWarning(`保存未成功：${error.message}。原台账未由本次操作覆盖，请导出待保存数据或重试。`);
      $('save-status').textContent = '保存失败 · 原台账仍保留';
      message(error.message, true); return false;
    }
  }
  function canEdit() {
    if (historyOpen) { message('历史周报只读，请先返回当前台账。', true); return false; }
    if (storageBroken || pendingState) { message('请先处理顶部的存储异常，导出数据或重试保存。', true); return false; }
    return true;
  }
  function download(textOrBytes, name, type = 'application/json') {
    const url = URL.createObjectURL(new Blob([textOrBytes], { type }));
    const a = document.createElement('a'); a.href = url; a.download = name; document.body.append(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 30000);
  }
  function backup(data = state) { return JSON.stringify({ ...data, exportedAt: new Date().toISOString() }, null, 2); }
  function exportJSON(data = state, prefix = '稽核完整备份') {
    download(backup(data), `${prefix}_${K.localDate()}_${Date.now()}.json`);
    message('已发起备份下载，请检查浏览器下载目录。');
  }
  function filters() { return { query: $('search').value, module: $('module-filter').value, status: $('status-filter').value, owner: personalView ? personName : $('owner-filter').value }; }
  function currentSnapshot() { return state.snapshots.find(s => s.id === selectedSnapshot); }
  function viewRecords() { return historyOpen ? (currentSnapshot() || { records: [] }).records : personalView ? state.records.filter(r => r.owner === personName) : state.records; }
  function visibleRecords() { return K.filtered(viewRecords(), filters(), historyOpen); }
  function selectOptions(select, entries, emptyText, previous = select.value) {
    select.replaceChildren(option('', emptyText), ...entries.map(e => option(e.value, e.label)));
    select.value = entries.some(e => e.value === previous) ? previous : '';
  }
  function renderStats(records) {
    const s = K.stats(records, historyOpen);
    $('stats').replaceChildren();
    [{ key: 'total', label: '工作总数', foot: '当前筛选范围内的全部工作' },
      ...['overdue', 'normal', 'completed'].map(key => ({ key, label: C.statuses[key].label,
        foot: key === 'normal' ? '交付日期未过 · 持续跟进' : key === 'overdue' ? '交付日期已过 · 优先关注' : '整项工作已完成' }))].forEach(item => {
      const card = button('', () => { $('status-filter').value = item.key === 'total' ? '' : item.key; render(); }, 'stat'); card.dataset.stat = item.key;
      card.setAttribute('aria-label', `${item.label} ${s[item.key]} 项，点击筛选`);
      card.setAttribute('aria-pressed', String(item.key !== 'total' && filters().status === item.key));
      const label = el('div', undefined, 'stat-label');
      if (item.key !== 'total') { const dot = el('span', undefined, 'status-dot'); dot.style.background = C.statuses[item.key].color; label.append(dot); }
      label.append(el('span', item.label));
      const value = el('div', String(s[item.key]), 'stat-value'); value.append(el('small', '项'));
      card.append(label, value, el('div', item.foot, 'stat-foot')); $('stats').append(card);
    });
    $('overdue-notice').hidden = s.overdue === 0;
    $('overdue-notice').textContent = `${historyOpen ? '周报保存时' : '当前筛选内'}有 ${s.overdue} 项工作已逾期，请关注交付与下一步安排。`;
    $('result-count').textContent = `显示 ${records.length} 项`;
    $('module-nav').replaceChildren(...C.modules.map(m => {
      const b = button(m.label, () => { $('module-filter').value = m.id; render(); }, 'nav-item');
      if (filters().module === m.id) b.classList.add('active');
      b.append(el('span', String(s.modules[m.id]), 'nav-count')); return b;
    }));
  }
  function card(record) {
    const status = historyOpen ? record.frozenStatus : K.status(record);
    const article = el('article', undefined, `work-card work-item ${status}`); article.dataset.recordId = record.id;
    const top = el('div', undefined, 'card-top');
    top.append(el('h3', record.name), el('span', C.statuses[status].label, `badge ${status}`));
    const meta = el('div', undefined, 'card-meta');
    meta.append(el('span', `负责人  ${record.owner}`), el('span', `交付  ${record.dueDate}`, status === 'overdue' ? 'late' : ''));
    const content = el('div', undefined, 'card-content');
    const progress = K.percent(record), progressBox = el('div', undefined, 'progress-box');
    const progressLabel = el('div', undefined, 'progress-label');
    progressLabel.append(el('span', '项目进度'), el('strong', progress === null ? '未填写' : `${progress}%`));
    const track = el('div', undefined, 'progress-track');
    if (progress !== null) {
      track.setAttribute('role', 'progressbar'); track.setAttribute('aria-label', `${record.name}项目进度`);
      track.setAttribute('aria-valuemin', '0'); track.setAttribute('aria-valuemax', '100'); track.setAttribute('aria-valuenow', String(progress));
      const fill = el('div', undefined, 'progress-fill'); fill.style.width = `${progress}%`; track.append(fill);
    }
    progressBox.append(progressLabel, track);
    C.board.textFields.forEach(key => {
      const f = K.fieldsFor(record.module).find(f => f.key === key);
      if (!f) return;
      const row = el('div', undefined, `card-field ${key === 'nextPlan' ? 'next' : ''}`);
      row.append(el('span', f.label), el('span', String(record[key] || (key === 'nextPlan' && record.completed ? '整项工作已完成' : '—')))); content.append(row);
    });
    const bottom = el('div', undefined, 'card-bottom');
    const time = el('span', `更新于 ${stamp(record.updatedAt)}`); time.title = `唯一编号：${record.id}`;
    bottom.append(time);
    if (!historyOpen) {
      const actions = el('div');
      actions.append(button('更新进展', () => openEditor(record), 'update-action')); bottom.append(actions);
    }
    article.append(top, meta, progressBox, content, bottom); return article;
  }
  function showDetail(record) {
    detailRecord = record; $('detail-title').textContent = record.name;
    const content = card(record); content.querySelectorAll('.update-action').forEach(node => node.remove());
    $('detail-body').replaceChildren(content); $('detail-edit').hidden = historyOpen;
    show('detail-dialog');
  }
  function listTable(records) {
    const wrap = el('div', undefined, 'table-wrap'), table = el('table', undefined, 'work-table');
    const thead = el('thead'), heading = el('tr');
    ['工作事项 / 负责人', '项目进度', '交付日期 / 状态', '现阶段进展', '下一步计划', '操作'].forEach(name => { const th = el('th', name); th.scope = 'col'; heading.append(th); });
    thead.append(heading); table.append(thead);
    const tbody = el('tbody');
    records.forEach(record => {
      const status = historyOpen ? record.frozenStatus : K.status(record);
      const row = el('tr', undefined, `work-item ${status}`); row.dataset.recordId = record.id;
      const title = el('td', undefined, 'name-cell'); title.append(button(record.name, () => showDetail(record), 'record-name'), el('span', record.owner, 'row-owner'));
      const progressCell = el('td', undefined, 'percent-cell'), pct = K.percent(record);
      const progressLabel = el('div', undefined, 'progress-label'); progressLabel.append(el('strong', pct === null ? '未填写' : `${pct}%`));
      const track = el('div', undefined, 'progress-track');
      if (pct !== null) {
        track.setAttribute('role', 'progressbar'); track.setAttribute('aria-label', `${record.name}项目进度`);
        track.setAttribute('aria-valuemin', '0'); track.setAttribute('aria-valuemax', '100'); track.setAttribute('aria-valuenow', String(pct));
        const fill = el('div', undefined, 'progress-fill'); fill.style.width = `${pct}%`; track.append(fill);
      }
      progressCell.append(progressLabel, track);
      const due = el('td', undefined, 'due-cell'); due.append(el('span', record.dueDate, 'row-date'), el('span', C.statuses[status].label, `badge ${status}`));
      const progressText = el('td', undefined, 'row-text'); progressText.dataset.label = '现阶段进展';
      const progressP = el('p', record.progress || '暂未填写'); progressP.title = record.progress || ''; progressText.append(progressP);
      const nextText = el('td', undefined, 'row-text'); nextText.dataset.label = '下一步计划';
      const nextP = el('p', record.nextPlan || (record.completed ? '整项工作已完成' : '暂未填写')); nextP.title = record.nextPlan || ''; nextText.append(nextP);
      const actions = el('td', undefined, 'action-cell');
      actions.append(button(historyOpen ? '查看详情' : '更新进展', () => historyOpen ? showDetail(record) : openEditor(record), 'update-action'));
      row.append(title, progressCell, due, progressText, nextText, actions); tbody.append(row);
    });
    table.append(tbody); wrap.append(table); return wrap;
  }
  function render() {
    if (selectedSnapshot && !currentSnapshot()) selectedSnapshot = '';
    const source = viewRecords();
    const owners = [...new Set([...source.map(r => r.owner), ...(personalView ? [personName] : [])])].sort((a, b) => a.localeCompare(b, 'zh-CN'));
    selectOptions($('owner-filter'), owners.map(x => ({ value: x, label: x })), '全部负责人');
    if (personalView) $('owner-filter').value = personName;
    $('owner-filter').disabled = personalView;
    const records = visibleRecords().sort((a, b) => C.board.defaultSort === 'updatedAt' ? b.updatedAt.localeCompare(a.updatedAt) : a.dueDate.localeCompare(b.dueDate) || a.name.localeCompare(b.name, 'zh-CN'));
    renderStats(records);
    $('page-title').textContent = historyOpen ? '历史周报' : personalView ? '我的工作' : C.appName;
    $('breadcrumb').textContent = historyOpen ? '历史周报' : personalView ? '我的工作' : '部门看板';
    $('page-subtitle').textContent = historyOpen ? '查看每周留档，进度与状态保持当时的记录。' : personalView ? '找到你的工作，更新进展，再下载文件交给汇总同事。' : '各项进度一目了然，优先跟进逾期事项。';
    $('board-title').textContent = historyOpen ? '已留档工作' : personalView ? '我负责的工作' : '部门工作清单';
    $('current-view').classList.toggle('active', !historyOpen && !personalView); $('history-button').classList.toggle('active', historyOpen);
    $('my-view').classList.toggle('active', personalView);
    $('personal-strip').hidden = !personalView; $('personal-label').textContent = `填报人：${personName}`;
    $('workflow-guide').hidden = historyOpen || personalView;
    $('submit-button').hidden = !personalView; $('import-button').hidden = personalView;
    $('snapshot-button').hidden = personalView || historyOpen;
    $('list-view').setAttribute('aria-pressed', String(displayMode === 'list')); $('card-view').setAttribute('aria-pressed', String(displayMode === 'cards'));
    $('history-panel').hidden = !historyOpen; $('snapshot-count').textContent = String(state.snapshots.length);
    selectOptions($('snapshot-select'), state.snapshots.slice().sort((a, b) => b.savedAt.localeCompare(a.savedAt)).map(s => ({ value: s.id, label: `${s.week} 所属周 · ${stamp(s.savedAt)} · ${s.records.length} 项` })), '请选择周报', selectedSnapshot);
    const shot = currentSnapshot();
    $('snapshot-info').textContent = shot ? `留档日期 ${shot.asOfDate} · 共 ${shot.records.length} 项工作 · 仅供查看` : '还没有历史周报。请在部门看板点击“本周留档”。';
    $('delete-snapshot').disabled = !shot;
    ['add-button', 'import-button', 'snapshot-button'].forEach(id => { $(id).disabled = historyOpen || storageBroken || !!pendingState; });
    $('export-json').disabled = storageBroken;
    $('submit-button').disabled = historyOpen || storageBroken || !!pendingState || !state.records.some(r => r.owner === personName);
    $('board').replaceChildren();
    if (!records.length) {
      const empty = el('div', undefined, 'empty-state');
      empty.append(el('div', '▤', 'empty-icon'), el('h3', historyOpen ? '暂无可显示的历史工作' : personalView ? '还没有找到你的工作' : source.length ? '没有符合筛选条件的工作' : '先添加一项工作，或汇总同事的进展'),
        el('p', personalView ? '核对负责人姓名是否一致，也可以直接新增你负责的工作。' : source.length ? '调整筛选条件，或点击“重置”查看全部工作。' : historyOpen ? '选择一份已保存的周报，回看当时进展。' : '个人填报请先点击左侧“我的工作”；汇总同事可直接上传收到的提交文件。'));
      if (!historyOpen && !source.length) empty.append(button('＋ 新增第一项工作', () => openEditor(), 'primary'));
      $('board').append(empty);
    }
    C.modules.filter(m => !filters().module || filters().module === m.id).forEach((m) => {
      const list = records.filter(r => r.module === m.id);
      if (!list.length && !C.board.showEmptyModules) return;
      const section = el('section', undefined, 'module-section');
      const heading = el('div', undefined, 'module-heading');
      heading.append(el('span', String(C.modules.indexOf(m) + 1).padStart(2, '0'), 'module-index'), el('h3', m.label), el('span', String(list.length), 'count'));
      if (!historyOpen) heading.append(button('＋ 添加工作', () => openEditor(null, m.id), 'text-button'));
      section.append(heading);
      if (list.length && displayMode === 'list') section.append(listTable(list));
      else if (list.length) { const grid = el('div', undefined, 'cards'); grid.append(...list.map(card)); section.append(grid); }
      else section.append(el('div', '当前范围暂无工作记录', 'empty-module'));
      $('board').append(section);
    });
  }
  function renderFields(values) {
    $('record-fields').replaceChildren();
    for (const f of K.fieldsFor($('record-module').value)) {
      const label = el('label', f.label, f.type === 'textarea' || f.type === 'boolean' ? 'full' : '');
      if (f.required || f.requiredWhenOpen) label.append(el('span', ' *', 'required'));
      const input = el(f.type === 'textarea' ? 'textarea' : 'input'); input.name = f.key; input.id = `field-${f.key}`;
      if (f.type !== 'textarea') input.type = f.type === 'boolean' ? 'checkbox' : f.type;
      if (f.type === 'boolean') { input.checked = !!values[f.key]; label.classList.add('check-label'); }
      else { input.value = values[f.key] ?? ''; input.maxLength = f.maxLength || 4000; }
      if (f.type === 'number') { input.min = f.min; input.max = f.max; input.step = f.step || 'any'; }
      if (f.key === 'progressPercent') {
        input.placeholder = '0–100；空白表示未填写';
        if (values.completed) { input.value = 100; input.disabled = true; }
      }
      if (f.type === 'date') { input.min = '1900-01-01'; input.max = '9999-12-31'; }
      if (f.type !== 'boolean') input.required = !!f.required || !!(f.requiredWhenOpen && !values.completed);
      label.append(input);
      if (f.type === 'boolean') label.append(el('span', '勾选表示整项工作已完成', 'field-help'));
      if (f.key === 'progressPercent') label.append(el('p', '手动填写整数百分比；100% 不自动确认完成，整项结束后请勾选“是否完成”。', 'field-help'));
      $('record-fields').append(label);
      if (f.key === 'owner') { input.setAttribute('list', 'person-options'); input.placeholder = '填写实际负责人姓名'; }
      if (f.key === 'name') input.placeholder = '例如：采购流程专项稽核';
      if (f.key === 'progress') input.placeholder = '已完成哪些工作？目前有哪些问题或待确认事项？';
      if (f.key === 'nextPlan') input.placeholder = '下一步准备做什么？需要谁配合？';
      if (f.key === 'progressPercent') {
        const presets = el('div', undefined, 'progress-presets');
        [0, 25, 50, 75, 100].forEach(n => { const b = button(`${n}%`, () => { input.value = n; }, 'progress-preset'); b.disabled = !!values.completed; presets.append(b); });
        label.append(presets);
      }
      if (f.key === 'completed') input.addEventListener('change', updateRequired);
    }
  }
  function updateRequired() {
    const done = $('field-completed').checked;
    const percentInput = $('field-progressPercent');
    if (percentInput) { percentInput.disabled = done; if (done) percentInput.value = 100; }
    document.querySelectorAll('.progress-preset').forEach(b => { b.disabled = done; });
    K.fieldsFor($('record-module').value).forEach(f => { if (f.requiredWhenOpen) $(`field-${f.key}`).required = !!f.required || !done; });
  }
  function formValues() {
    const values = {};
    K.fieldsFor($('record-module').value).forEach(f => { const input = $(`field-${f.key}`); if (input) values[f.key] = f.type === 'boolean' ? input.checked : f.type === 'number' ? input.value === '' ? null : Number(input.value) : input.value.trim(); });
    return values;
  }
  let editorDraft = {};
  function openEditor(record, module = C.modules[0].id) {
    if (!canEdit()) return;
    editingId = record ? record.id : null; editorDraft = record ? K.clone(record) : { progressPercent: 0, owner: personName };
    $('editor-title').textContent = record ? '更新进展' : '新增工作';
    $('editor-delete').hidden = !record;
    $('editor-dialog').querySelector('.record-info').open = false;
    $('person-options').replaceChildren(...[...new Set(state.records.map(r => r.owner))].map(name => option(name, name)));
    $('record-meta').textContent = record ? `唯一编号：${record.id}` : '保存时自动生成唯一编号，后续提交和更新请保持编号不变。';
    $('record-module').value = record ? record.module : module;
    renderFields(editorDraft); errorAt('editor-error', null); show('editor-dialog');
  }
  function resetFilters() { ['search', 'module-filter', 'status-filter', 'owner-filter'].forEach(id => { $(id).value = ''; }); }
  function changeView(history) {
    historyOpen = history; personalView = false; resetFilters();
    if (history && !selectedSnapshot && state.snapshots.length) selectedSnapshot = state.snapshots.slice().sort((a, b) => b.savedAt.localeCompare(a.savedAt))[0].id;
    render();
  }
  function choosePerson(action = 'view') {
    personAction = action; $('person-name').value = personName;
    $('person-options').replaceChildren(...[...new Set(state.records.map(r => r.owner))].map(name => option(name, name)));
    show('person-dialog');
  }
  function myView() { historyOpen = false; personalView = true; resetFilters(); render(); }
  function renderMerge() {
    $('import-preview').replaceChildren();
    const counts = { new: 0, same: 0, conflict: 0 }; mergePlan.forEach(item => counts[item.kind]++);
    $('import-summary').textContent = `新增 ${counts.new} 项 · 相同跳过 ${counts.same} 项 · 冲突 ${counts.conflict} 项。未选择的冲突保留当前版。`;
    mergePlan.forEach(item => {
      const box = el('article', undefined, `merge-item ${item.kind}`);
      box.append(el('h3', `${{ new: '新工作', same: '内容相同，无需更新', conflict: '内容有变化，请选择' }[item.kind]} · ${item.record.name}`), el('p', `${K.moduleName(item.record.module)} · ${item.record.owner}`, 'muted'));
      const identity = el('details', undefined, 'record-info'); identity.append(el('summary', '记录编号'), el('p', item.record.id, 'muted')); box.append(identity);
      if (item.warning) box.append(el('p', item.warning, 'merge-warning'));
      // 新记录也展示全部业务字段，便于在提交前核对。
      if (item.kind !== 'same') {
        const table = el('table'); const head = el('tr');
        head.append(el('th', '字段')); if (item.existing) head.append(el('th', '当前内容')); head.append(el('th', '导入内容'));
        const thead = el('thead'); thead.append(head); table.append(thead); const tbody = el('tbody');
        [{ key: 'module', label: '模块' }, ...C.fields.filter(f => !f.legacy || item.record[f.key] || (item.existing && item.existing[f.key])), { key: 'updatedAt', label: '更新时间' }].forEach(f => {
          const format = r => f.key === 'module' ? K.moduleName(r.module) : f.type === 'boolean' ? r[f.key] ? '是' : '否' : String(r[f.key] ?? '');
          const tr = el('tr'); if (item.existing && format(item.existing) !== format(item.record)) tr.className = 'changed';
          tr.append(el('td', f.label)); if (item.existing) tr.append(el('td', format(item.existing))); tr.append(el('td', format(item.record))); tbody.append(tr);
        }); table.append(tbody); box.append(table);
      }
      if (item.kind === 'conflict') {
        const label = el('label', '选择采用的版本'); const select = el('select'); select.dataset.choiceId = item.record.id;
        select.append(option('current', '保留已有内容（默认）'), option('incoming', '采用同事提交的内容')); label.append(select); box.append(label);
      }
      $('import-preview').append(box);
    });
    $('duplicate-ack-wrap').hidden = !mergePlan.some(x => x.warning);
    $('duplicate-ack').checked = false; updateImportButton();
  }
  function updateImportButton() {
    $('commit-import').disabled = !mergePlan.length || (mergePlan.some(x => x.warning) && !$('duplicate-ack').checked);
  }
  function checkFile(file, extensions) {
    if (!file) throw new Error('请选择文件');
    if (file.size > C.limits.maxFileBytes) throw new Error(`文件超过 ${C.limits.maxFileBytes / 1024 / 1024} MB 上限`);
    if (!extensions.some(ext => file.name.toLowerCase().endsWith(ext))) throw new Error(`请选择 ${extensions.join(' 或 ')} 文件`);
  }
  // 绑定入口。表单和导入中的字符串只用 textContent 展示，不拼接成 HTML。
  document.querySelectorAll('[data-close]').forEach(b => b.addEventListener('click', () => close(b.dataset.close)));
  $('add-button').onclick = () => openEditor();
  $('record-module').addEventListener('change', () => {
    // 先按实际已渲染控件收集，避免切换模块时丢掉共用字段和临时输入。
    $('record-fields').querySelectorAll('input,textarea').forEach(input => { editorDraft[input.name] = input.type === 'checkbox' ? input.checked : input.value; });
    renderFields(editorDraft);
  });
  $('editor-form').onsubmit = event => {
    event.preventDefault();
    if (!canEdit()) return;
    const record = { id: editingId || K.id(), module: $('record-module').value, ...formValues(), updatedAt: new Date().toISOString() };
    // 隐藏的旧字段仍保留在原编号中，避免日常编辑删掉历史说明。
    const existing = state.records.find(r => r.id === editingId);
    if (existing) C.fields.filter(f => f.legacy && K.own(existing, f.key)).forEach(f => { record[f.key] = existing[f.key]; });
    const errors = K.validateRecord(record);
    if (errors.length) { errorAt('editor-error', errors.join('\n')); return; }
    const duplicate = state.records.some(r => r.id !== record.id && r.module === record.module && r.name === record.name && r.owner === record.owner);
    if (duplicate && !confirm('已有同模块、同名称、同负责人的其他编号。确认这是另一项工作并继续保存？')) return;
    const next = K.clone(state), index = next.records.findIndex(r => r.id === record.id);
    if (index >= 0) next.records[index] = record; else next.records.push(record);
    if (commit(next, editingId ? '工作已更新。' : '工作已新增。')) close('editor-dialog');
    else errorAt('editor-error', '保存未成功，输入仍保留。请关闭弹窗并处理顶部存储提示。');
  };
  $('current-view').onclick = $('return-current').onclick = () => changeView(false);
  $('my-view').onclick = () => personName ? myView() : choosePerson();
  $('change-person').onclick = () => choosePerson();
  $('person-name').oninput = () => $('person-name').setCustomValidity('');
  $('person-form').onsubmit = event => {
    event.preventDefault(); const name = $('person-name').value.trim(); if (!name) { $('person-name').setCustomValidity('请填写负责人姓名'); $('person-name').reportValidity(); return; }
    personName = name; savePreferences(); close('person-dialog'); myView();
    if (personAction === 'submit') submitMine();
  };
  $('list-view').onclick = () => { displayMode = 'list'; savePreferences(); render(); };
  $('card-view').onclick = () => { displayMode = 'cards'; savePreferences(); render(); };
  $('detail-edit').onclick = () => { close('detail-dialog'); if (detailRecord) openEditor(detailRecord); };
  $('detail-dialog').addEventListener('close', () => $('detail-body').replaceChildren());
  $('editor-delete').onclick = () => {
    if (!canEdit() || !editingId) return;
    const record = state.records.find(r => r.id === editingId);
    if (record && confirm(`删除“${record.name}”？历史周报仍然保留，其他同事的文件不会改变。`)) {
      const next = K.clone(state); next.records = next.records.filter(r => r.id !== editingId);
      if (commit(next, '工作已删除，历史周报仍然保留。')) close('editor-dialog');
    }
  };
  $('history-button').onclick = () => changeView(true);
  $('snapshot-select').onchange = () => { selectedSnapshot = $('snapshot-select').value; render(); };
  ['module-filter', 'status-filter', 'owner-filter'].forEach(id => { $(id).onchange = render; });
  $('search').oninput = render; $('clear-filters').onclick = () => { resetFilters(); render(); };
  $('help-button').onclick = () => show('help-dialog');
  $('snapshot-button').onclick = () => { if (canEdit()) { $('snapshot-week').value = K.monday(); errorAt('snapshot-error', null); show('snapshot-dialog'); } };
  $('snapshot-form').onsubmit = event => {
    event.preventDefault();
    if (!canEdit()) return;
    try {
      if (state.snapshots.length >= C.limits.maxSnapshots) throw new Error('周报已达上限，请导出备份后删除不需要的周报');
      const next = K.clone(state); next.snapshots.push(K.snapshot(state.records, $('snapshot-week').value));
      if (commit(next, '周周报已保存，历史状态已固定。')) close('snapshot-dialog');
      else errorAt('snapshot-error', '保存失败，请处理顶部存储提示。');
    } catch (e) { errorAt('snapshot-error', e); }
  };
  $('delete-snapshot').onclick = () => {
    const s = currentSnapshot();
    if (!s || storageBroken || pendingState) return;
    if (confirm(`删除 ${s.week} 所属周、${stamp(s.savedAt)} 保存的周报？建议先导出完整备份。`)) {
      const next = K.clone(state); next.snapshots = next.snapshots.filter(x => x.id !== s.id); commit(next, '周报已删除，当前台账未改变。');
    }
  };
  $('export-button').onclick = () => { $('export-scope').value = 'all'; show('export-dialog'); };
  function exportExcel(records, template = false, personal = false) {
    try {
      const wb = E.workbook(records, { frozen: historyOpen && !template });
      const bytes = XLSX.write(wb, { type: 'array', bookType: 'xlsx', compression: true });
      const safeName = personName.replace(/[\\/:*?"<>|\u0000-\u001f]/g, '_');
      download(bytes, `${template ? '稽核填写模板' : personal ? `工作进展_${safeName}` : historyOpen ? '稽核历史周报' : '稽核工作台账'}_${K.localDate()}.xlsx`, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      message(personal ? '已开始下载你的工作文件。请到浏览器“下载内容”中找到文件，发送给部门汇总同事；本页面不会自动发送。' : '已开始下载 Excel，请到浏览器“下载内容”中查看。');
    } catch (e) { message(e.message, true); }
  }
  $('template-button').onclick = () => exportExcel([], true);
  function submitMine() {
    if (!personName) { choosePerson('submit'); return; }
    if (storageBroken || pendingState) { message('请先处理未保存的工作，再下载提交文件。', true); return; }
    const mine = state.records.filter(r => r.owner === personName);
    if (!mine.length) { message('还没有找到你负责的工作，请核对姓名或先新增工作。', true); return; }
    // 下载全部个人记录，不受搜索或模块筛选影响，防止漏报。
    exportExcel(mine, false, true);
  }
  $('submit-button').onclick = submitMine;
  $('download-view').onclick = () => exportExcel(visibleRecords());
  $('export-xlsx').onclick = () => { exportExcel($('export-scope').value === 'filtered' ? visibleRecords() : viewRecords()); close('export-dialog'); };
  $('export-json').onclick = () => { exportJSON(); close('export-dialog'); };
  $('emergency-export').onclick = () => exportJSON(pendingState || state, '稽核待保存数据');
  $('raw-export').onclick = () => download(loadedRaw ?? '', `稽核原始存储_${Date.now()}.txt`, 'text/plain');
  $('retry-save').onclick = () => { if (pendingState) commit(pendingState, '已重新保存待保存数据。', { retry: true }); };
  $('import-button').onclick = () => {
    if (!canEdit()) return;
    importSequence++; mergePlan = []; mergeBase = null; $('import-file').value = ''; $('import-preview').replaceChildren(); $('import-summary').textContent = '';
    errorAt('import-errors', null); $('duplicate-ack-wrap').hidden = true; updateImportButton(); show('import-dialog');
  };
  $('import-dialog').addEventListener('close', () => { importSequence++; });
  $('import-file').onchange = async () => {
    const sequence = ++importSequence; mergePlan = []; updateImportButton(); errorAt('import-errors', null); $('import-preview').replaceChildren(); $('duplicate-ack-wrap').hidden = true;
    $('import-summary').textContent = '正在读取和校验…';
    try {
      const file = $('import-file').files[0]; checkFile(file, ['.xlsx', '.json']);
      const incoming = file.name.toLowerCase().endsWith('.json') ? K.recordsFromImport(JSON.parse(await file.text())) : E.read(await file.arrayBuffer());
      if (sequence !== importSequence) return;
      mergeBase = loadedRaw; mergePlan = K.prepareMerge(state.records, incoming); renderMerge();
      if (!incoming.length) $('import-summary').textContent = '文件中没有工作记录，未进行任何修改。';
    } catch (e) { if (sequence === importSequence) { errorAt('import-errors', e); $('import-summary').textContent = '校验未通过，整批不会提交。'; mergePlan = []; updateImportButton(); } }
  };
  $('duplicate-ack').onchange = updateImportButton;
  $('commit-import').onclick = () => {
    if (!canEdit() || !mergePlan.length || $('commit-import').disabled) return;
    try {
      if (loadedRaw !== mergeBase) throw new Error('预览期间台账已改变，请重新选择文件生成预览');
      const choices = Object.create(null); $('import-preview').querySelectorAll('select[data-choice-id]').forEach(s => { choices[s.dataset.choiceId] = s.value; });
      const next = K.clone(state); next.records = K.applyMerge(state.records, mergePlan, choices);
      if (commit(next, '合并完成。未选择的冲突已保留当前版，已有周报保持不变。')) close('import-dialog');
      else errorAt('import-errors', '合并未保存，请处理顶部存储提示。');
    } catch (e) { errorAt('import-errors', e); }
  };
  $('restore-button').onclick = () => {
    close('export-dialog'); restoreSequence++; restoreCandidate = null; backupText = null; backupVerified = false;
    $('restore-file').value = ''; $('verify-backup-file').value = ''; $('restore-summary').textContent = ''; $('backup-verified').textContent = '';
    $('pre-restore-export').disabled = true; $('verify-backup-file').disabled = true; $('confirm-restore').disabled = true;
    errorAt('restore-error', null); show('restore-dialog');
  };
  $('restore-dialog').addEventListener('close', () => { restoreSequence++; });
  $('restore-file').onchange = async () => {
    const sequence = ++restoreSequence;
    restoreCandidate = null; backupVerified = false; backupText = null;
    $('pre-restore-export').disabled = true; $('verify-backup-file').disabled = true; $('confirm-restore').disabled = true;
    $('restore-summary').textContent = ''; $('backup-verified').textContent = ''; errorAt('restore-error', null);
    try {
      const file = $('restore-file').files[0]; checkFile(file, ['.json']);
      const candidate = K.validateBackup(JSON.parse(await file.text()));
      if (sequence !== restoreSequence) return;
      if (pendingState) throw new Error('请先处理待保存数据：导出并妥善保管后刷新页面，再执行恢复');
      restoreCandidate = candidate; restoreBase = loadedRaw;
      $('restore-summary').textContent = `文件有效：${candidate.records.length} 项工作、${candidate.snapshots.length} 份周报。将替换本机 ${state.records.length} 项工作、${state.snapshots.length} 份周报。`;
      $('pre-restore-export').disabled = false;
    } catch (e) { if (sequence === restoreSequence) errorAt('restore-error', e); }
  };
  $('pre-restore-export').onclick = () => {
    try {
      if (!restoreCandidate) return;
      backupText = storageBroken ? loadedRaw : backup(state);
      if (backupText === null) backupText = backup(state);
      download(backupText, `恢复前备份_${Date.now()}.${storageBroken ? 'txt' : 'json'}`, storageBroken ? 'text/plain' : 'application/json');
      backupVerified = false; $('confirm-restore').disabled = true; $('verify-backup-file').disabled = false; $('verify-backup-file').value = '';
      $('backup-verified').textContent = '备份下载已发起。请选择刚下载的文件，应用将核对内容是否完整一致。';
    } catch (e) { errorAt('restore-error', e); }
  };
  $('verify-backup-file').onchange = async () => {
    backupVerified = false; $('confirm-restore').disabled = true;
    const expected = backupText, sequence = restoreSequence;
    try {
      const file = $('verify-backup-file').files[0]; if (!file) return;
      if (file.size > Math.max(C.limits.maxFileBytes, new Blob([expected]).size)) throw new Error('选择的备份文件过大');
      const text = await file.text();
      if (sequence !== restoreSequence || expected !== backupText) return;
      if (text !== expected) throw new Error('所选文件与刚导出的当前备份不一致，请选择正确文件');
      backupVerified = true; $('confirm-restore').disabled = false; $('backup-verified').textContent = '当前数据备份校验通过，可执行完整恢复。'; errorAt('restore-error', null);
    } catch (e) { errorAt('restore-error', e); }
  };
  $('confirm-restore').onclick = () => {
    if (!restoreCandidate || !backupVerified) return;
    if (loadedRaw !== restoreBase) { errorAt('restore-error', '台账已改变，请重新开始恢复流程。'); return; }
    if (!confirm('已校验当前数据备份。确认用所选文件替换全部台账和周周报？')) return;
    if (commit(restoreCandidate, '完整恢复成功。', { restore: true })) { selectedSnapshot = ''; changeView(false); close('restore-dialog'); }
    else errorAt('restore-error', '恢复未保存，原数据仍保留。请处理顶部存储提示。');
  };
  window.addEventListener('storage', event => {
    if (event.key === stateKey && event.newValue !== loadedRaw) storageWarning('另一页面修改了本机台账。请先导出当前或待保存数据，再刷新并合并。');
  });
  // 跨午夜或从后台返回时更新当前状态；历史周报的 frozenStatus 不变。
  let lastDate = K.localDate();
  function refreshDate() {
    const today = K.localDate(); $('today').textContent = new Date().toLocaleDateString('zh-CN', { year: 'numeric', month: 'long', day: 'numeric', weekday: 'long' });
    if (today !== lastDate) { lastDate = today; render(); }
  }
  document.addEventListener('visibilitychange', refreshDate); window.addEventListener('focus', refreshDate); setInterval(refreshDate, 30000);
  Object.entries(C.statuses).forEach(([key, value]) => {
    document.documentElement.style.setProperty(`--${key}`, value.color); document.documentElement.style.setProperty(`--${key}-bg`, value.background);
  });
  Object.entries(C.theme).forEach(([key, value]) => document.documentElement.style.setProperty(`--${key.replace(/[A-Z]/g, letter => '-' + letter.toLowerCase())}`, value));
  selectOptions($('module-filter'), C.modules.map(m => ({ value: m.id, label: m.label })), '全部模块');
  selectOptions($('status-filter'), Object.entries(C.statuses).map(([key, s]) => ({ value: key, label: s.label })), '全部状态');
  $('record-module').append(...C.modules.map(m => option(m.id, m.label)));
  document.title = C.appName; initialize(); refreshDate(); render();
})();
