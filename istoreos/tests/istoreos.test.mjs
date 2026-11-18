import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import test from 'node:test';

// Offline checks only: no router access, no downloads, no flashing.

const read = (path) => readFileSync(new URL(path, import.meta.url), 'utf8');
const docs = {
  readme: read('../README.md'),
  guide: read('../使用指南.md'),
  agents: read('../AGENTS.md'),
};
const rootReadme = read('../../README.md');
const rootAgents = read('../../AGENTS.md');
const verifyScript = read('../scripts/verify.sh');

test('Documentation set is complete and keeps the promised sections', () => {
  for (const [name, text] of Object.entries(docs)) {
    assert.ok(text.trim().length > 500, `${name} is suspiciously short`);
  }
  for (const heading of ['## 优化清单', '## 关键结论', '## 本次实测结果', '## 与 `passwall/` 的分工', '## 回滚原则']) {
    assert.ok(docs.readme.includes(heading), `README is missing ${heading}`);
  }
  for (const heading of ['## 1. 先备份', '## 2. 升级 24.10 → 25.12', '## 4. 调整磁盘', '## 7. 验收清单', '## 9. 回滚']) {
    assert.ok(docs.guide.includes(heading), `guide is missing ${heading}`);
  }
  assert.ok(docs.agents.includes('## 执行协议') && docs.agents.includes('## 红线'));
});

test('Versions and sizes agree with the documented baseline', () => {
  const text = Object.values(docs).join('\n');
  for (const value of ['24.10.8', '25.12.6', '26.11.11', '16 GiB', '38.6G', '15.6G']) {
    assert.ok(text.includes(value), `docs do not mention ${value}`);
  }
});

test('Public docs contain no credentials, node endpoints or identifiers', () => {
  const text = Object.values(docs).join('\n') + verifyScript;
  assert.doesNotMatch(text, /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i, 'UUID found');
  assert.doesNotMatch(text, /(vless|vmess|ss|ssr|trojan|hysteria2?):\/\//i, 'proxy URI found');
  assert.doesNotMatch(text, /\b(password|passwd|private[_-]?key)\s*[:=]\s*\S+/i, 'credential assignment found');
  assert.doesNotMatch(text, /clearitly|graniterapids/i, 'provider domain found');
  assert.doesNotMatch(text, /\/sub\/[0-9a-f]{6,}/i, 'subscription path found');
  assert.doesNotMatch(text, /\b([0-9A-F]{2}:){5}[0-9A-F]{2}\b/i, 'MAC address found');

  const allowedIps = new Set(['0.0.0.0', '223.5.5.5', '1.1.1.1', '8.8.8.8']);
  for (const match of text.matchAll(/\b\d{1,3}(?:\.\d{1,3}){3}\b/g)) {
    const ip = match[0];
    if (allowedIps.has(ip)) continue;
    assert.match(ip, /^(10\.|127\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|169\.254\.)/,
      `unexpected public IP in docs: ${ip}`);
  }
});

test('Relative links in the new docs resolve', () => {
  for (const [name, text] of Object.entries(docs)) {
    const base = new URL(`../${name}`, import.meta.url);
    for (const match of text.matchAll(/\]\(([^)\s]+)\)/g)) {
      const target = match[1];
      if (/^(https?:|mailto:|#)/.test(target)) continue;
      const path = target.split('#')[0];
      if (!path) continue;
      assert.ok(existsSync(new URL(path, new URL('./', base))), `${name}: broken link ${target}`);
    }
  }
});

test('The verify script is read-only and checks the key surfaces', () => {
  assert.doesNotMatch(verifyScript, /\b(rm|mkfs\.ext4|sysupgrade|firstboot|reboot|parted)\b/,
    'verify.sh must not modify the system');
  for (const probe of ['/overlay', '/mnt/data', 'luci-app-passwall', 'input_wan', 'dpanel']) {
    assert.ok(verifyScript.includes(probe), `verify.sh does not check ${probe}`);
  }
});

test('Root navigation lists the istoreos project', () => {
  assert.ok(rootReadme.includes('./istoreos/README.md'));
  assert.ok(rootReadme.includes('./istoreos/使用指南.md'));
  assert.ok(rootAgents.includes('istoreos/'));
});
