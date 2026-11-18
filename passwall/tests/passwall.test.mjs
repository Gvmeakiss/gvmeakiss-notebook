import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import test from 'node:test';

// Offline regression checks only: they do not read the router, download rules or
// emulate Passwall. They guard list hygiene, documentation consistency and secrets.

const read = (path) => readFileSync(new URL(path, import.meta.url), 'utf8');
const docs = {
  readme: read('../README.md'),
  guide: read('../使用指南.md'),
  agents: read('../AGENTS.md'),
};
const rootReadme = read('../../README.md');
const rootAgents = read('../../AGENTS.md');

const domainLines = (text) => text.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
const isDomain = (line) => /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/.test(line);
const overlaps = (a, b) => a.filter((left) => b.some((right) =>
  left === right || left.endsWith(`.${right}`) || right.endsWith(`.${left}`)));

const directAdditions = domainLines(read('../direct-additions.txt'));
const proxyAdditions = domainLines(read('../proxy-additions.txt'));
const merlinDirect = domainLines(read('../../merlin/direct-domains.txt'));
const merlinProxy = domainLines(read('../../merlin/proxy-domains.txt'));

test('Documentation set is complete and keeps the promised sections', () => {
  for (const [name, text] of Object.entries(docs)) {
    assert.ok(text.trim().length > 500, `${name} is suspiciously short`);
  }
  for (const heading of ['## 分流与规则顺序', '## 参数基线', '## 名单怎么合并', '## 没有照抄的项', '## 实测记录', '## 边界']) {
    assert.ok(docs.readme.includes(heading), `README is missing ${heading}`);
  }
  for (const heading of ['## 1. 先备份', '## 2. 合并名单', '## 5. 应用与验收', '## 7. 回滚']) {
    assert.ok(docs.guide.includes(heading), `guide is missing ${heading}`);
  }
  assert.ok(docs.agents.includes('## 执行协议') && docs.agents.includes('## 红线'),
    'AGENTS must keep the protocol and red-line sections');
});

test('Addition lists are lowercase, plain, unique domains', () => {
  for (const [name, list] of [['direct-additions.txt', directAdditions], ['proxy-additions.txt', proxyAdditions]]) {
    assert.ok(list.length > 0, `${name} is empty`);
    for (const line of list) {
      assert.equal(line, line.toLowerCase(), `${name}: ${line} is not lowercase`);
      assert.ok(!line.startsWith('#'), `${name}: comment lines are not part of the list format`);
      assert.ok(!line.includes('*'), `${name}: ${line} uses a wildcard`);
      assert.ok(isDomain(line), `${name}: ${line} is not a plain domain`);
    }
    assert.equal(new Set(list).size, list.length, `${name} contains duplicates`);
  }
});

test('Counts agree between files and documentation', () => {
  assert.equal(merlinDirect.length, 119);
  assert.equal(merlinProxy.length, 49);
  assert.equal(directAdditions.length, 25);
  assert.equal(proxyAdditions.length, 17);

  const directTotal = merlinDirect.length + directAdditions.length;
  const proxyTotal = merlinProxy.length + proxyAdditions.length;
  assert.equal(directTotal, 144);
  assert.equal(proxyTotal, 66);

  for (const total of [119, 49, 25, 17, 144, 66]) {
    assert.ok(docs.readme.includes(String(total)), `README does not mention ${total}`);
  }
});

test('Neither lists nor additions overlap, parents included', () => {
  assert.deepEqual(overlaps(directAdditions, proxyAdditions), []);
  assert.deepEqual(overlaps(directAdditions, merlinProxy), []);
  assert.deepEqual(overlaps(proxyAdditions, merlinDirect), []);
  assert.deepEqual(overlaps(directAdditions, merlinDirect), []);
  assert.deepEqual(overlaps(proxyAdditions, merlinProxy), []);
});

test('apple-relay is excluded and the conflict is documented', () => {
  assert.ok(!proxyAdditions.includes('apple-relay.apple.com'));
  assert.ok(directAdditions.includes('apple.com'));
  assert.match(docs.readme, /apple-relay\.apple\.com/);
  assert.match(docs.readme, /apple\.com/);
});

test('Public docs contain no credentials, endpoints or real public IPs', () => {
  const allowedIps = new Set(['127.0.0.1', '223.5.5.5', '1.1.1.1', '8.8.8.8', '8.8.4.4', '9.9.9.9', '119.29.29.29']);
  const text = Object.values(docs).join('\n');
  assert.doesNotMatch(text, /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i, 'UUID found');
  assert.doesNotMatch(text, /(vless|vmess|ss|ssr|trojan|hysteria2?):\/\//i, 'proxy URI found');
  assert.doesNotMatch(text, /\b(password|passwd|private[_-]?key)\s*[:=]\s*\S+/i, 'credential assignment found');
  assert.doesNotMatch(text, /\/sub\/|subscription\.php/i, 'subscription path found');
  assert.doesNotMatch(text, /\b192\.168\.\d+\.\d+\b/, 'LAN address should stay a placeholder');

  for (const match of text.matchAll(/\b\d{1,3}(?:\.\d{1,3}){3}\b/g)) {
    assert.ok(allowedIps.has(match[0]), `unexpected public IP in docs: ${match[0]}`);
  }
});

test('Rule update command is the working one', () => {
  assert.ok(docs.guide.includes('rule_update.lua log'));
  for (const line of docs.guide.split(/\r?\n/)) {
    if (!line.includes('rule_update.lua log all')) continue;
    assert.match(line, /cron|不|无效|不会/, `log all must not be presented as a working command: ${line}`);
  }
});

test('All-port advice stays conditional', () => {
  assert.match(docs.readme, /### TCP 端口：不要照抄/);
  const text = Object.values(docs).join('\n');
  for (const line of text.split(/\r?\n/)) {
    if (!line.includes('1:65535')) continue;
    assert.match(line, /不要|不把|限制|超时|黑洞|回退/, `all-port advice lost its caveat: ${line}`);
  }
});

test('Relative links in the new docs resolve to tracked files', () => {
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

test('Root navigation lists the new project', () => {
  assert.ok(rootReadme.includes('./passwall/README.md'));
  assert.ok(rootReadme.includes('./passwall/使用指南.md'));
  assert.ok(rootAgents.includes('passwall/'));
  assert.match(docs.guide, /nslookup/);
  assert.match(docs.guide, /nft list set/);
  assert.match(docs.guide, /curl /);
});
