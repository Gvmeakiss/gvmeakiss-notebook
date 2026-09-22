import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { isIP } from 'node:net';
import test from 'node:test';

// Offline regression checks only: they do not download rules or emulate Shadowrocket.
const read = (path) => readFileSync(new URL(path, import.meta.url), 'utf8');
const config = read('../shadowrocket-optimized.conf');
const lines = (text) => text.split(/\r?\n/).map((line) => line.trim())
  .filter((line) => line && !line.startsWith('#'));
const sections = new Map();
const sectionNames = [];
let current;
for (const line of lines(config)) {
  const heading = line.match(/^\[([^\]]+)\]$/);
  if (heading) {
    current = heading[1];
    sectionNames.push(current);
    sections.set(current, []);
  } else {
    assert.ok(current, 'Every setting must belong to a section');
    sections.get(current).push(line);
  }
}
const rules = sections.get('Rule');
const index = (rule) => {
  const found = rules.indexOf(rule);
  assert.notEqual(found, -1, `Missing rule: ${rule}`);
  return found;
};
const nativeBase = 'https://cdn.jsdelivr.net/gh/blackmatrix7/ios_rule_script@master/rule/Shadowrocket/';
const ruleSet = (name, policy) => `RULE-SET,${nativeBase}${name}/${name}.list,${policy}`;
const aiSupplement = 'RULE-SET,https://cdn.jsdelivr.net/gh/iab0x00/ProxyRules@main/Rule/AI.txt,PROXY';

test('Only unique routing, DNS, hosts and safe rewrite sections are present', () => {
  assert.deepEqual(sectionNames, ['General', 'Rule', 'Host', 'URL Rewrite']);
  assert.equal(new Set(sectionNames).size, sectionNames.length);
  for (const name of ['General', 'Host']) {
    const keys = sections.get(name).map((line) => line.split('=', 1)[0].trim());
    assert.equal(new Set(keys).size, keys.length, `Duplicate ${name} key`);
  }
  // No embedded node/subscription credentials or TLS interception configuration.
  assert.doesNotMatch(config, /(?:ssr?|vmess|vless|trojan):\/\/|(?:password|token|uuid)\s*=/i);
  assert.doesNotMatch(config, /^(?:subscription|update-url|script|hostname|ca-p12)\s*=/mi);
});

test('DNS is portable between home Wi-Fi and mainland mobile networks', () => {
  const settings = Object.fromEntries(sections.get('General').map((line) => {
    const separator = line.indexOf('=');
    assert.ok(separator > 0);
    return [line.slice(0, separator).trim(), line.slice(separator + 1).trim()];
  }));
  const list = (key) => settings[key].split(',').map((value) => value.trim());
  assert.deepEqual(list('dns-server'), ['https://doh.pub/dns-query', 'https://dns.alidns.com/dns-query']);
  assert.deepEqual(list('fallback-dns-server'), ['223.5.5.5', '119.29.29.29', 'system']);
  assert.equal(settings['dns-direct-fallback-proxy'], 'false');
  assert.equal(settings['dns-direct-system'], 'false');
  assert.equal(settings['block-quic'], 'all-proxy');
  assert.deepEqual(list('hijack-dns'), ['8.8.8.8:53', '8.8.4.4:53', '1.1.1.1:53', '1.0.0.1:53']);
  assert.ok(sections.get('Host').includes('*.local = server:system'));
  assert.ok(sections.get('Host').includes('*.home.arpa = server:system'));
  assert.ok(sections.get('Host').every((line) => !/server:(?:10\.|172\.|192\.168\.)/.test(line)));
});

test('All 43 remote references retain their native format, source and policy', () => {
  const direct = 'Lan WeChat Zhihu DouYin BiliBili NetEaseMusic Baidu DouBan Sina XiaoHongShu SteamCN Microsoft Apple China'.split(' ');
  const proxy = 'OpenAI Gemini Claude Copilot YouTube Netflix Disney HBO Spotify Twitch Pixiv Telegram Twitter Facebook Instagram Whatsapp Discord Reddit Amazon Game GitHub Google TikTok Global'.split(' ');
  const expected = [
    ...direct.map((name) => ruleSet(name, 'DIRECT')),
    ...proxy.map((name) => ruleSet(name, 'PROXY')),
    ruleSet('Advertising', 'REJECT'),
    aiSupplement,
    ...[['Apple', 'DIRECT'], ['Global', 'PROXY'], ['China', 'DIRECT']]
      .map(([name, policy]) => `DOMAIN-SET,${nativeBase}${name}/${name}_Domain.list,${policy}`),
  ];
  const references = rules.filter((rule) => /^(?:RULE|DOMAIN)-SET,/.test(rule));
  assert.equal(references.length, 43);
  assert.equal(new Set(references).size, 43);
  assert.deepEqual([...references].sort(), expected.sort());
  for (const reference of references) {
    const url = new URL(reference.split(',')[1]);
    assert.equal(url.protocol, 'https:');
    assert.equal(url.username + url.password + url.search + url.hash, '');
  }
});

test('Rules use recognized local syntax and end in GEOIP then FINAL', () => {
  assert.equal(rules.length, 150);
  assert.equal(new Set(rules).size, rules.length);
  const allowed = new Set(['DOMAIN', 'DOMAIN-SUFFIX', 'IP-CIDR', 'RULE-SET', 'DOMAIN-SET', 'GEOIP', 'FINAL']);
  for (const rule of rules) {
    const fields = rule.split(',');
    assert.ok(allowed.has(fields[0]), `Unexpected rule type: ${fields[0]}`);
    if (fields[0] === 'FINAL') {
      assert.deepEqual(fields, ['FINAL', 'PROXY']);
      continue;
    }
    assert.ok(fields.length === 3 || (fields[0] === 'IP-CIDR' && fields.length === 4));
    assert.ok(['DIRECT', 'PROXY', 'REJECT'].includes(fields[2]));
    if (fields.length === 4) assert.equal(fields[3], 'no-resolve');
    if (fields[0] === 'IP-CIDR') {
      const [address, mask] = fields[1].split('/');
      const family = isIP(address);
      assert.ok(family && /^\d+$/.test(mask));
      assert.ok(Number(mask) >= 0 && Number(mask) <= (family === 4 ? 32 : 128));
    }
  }
  assert.deepEqual(rules.slice(-2), ['GEOIP,CN,DIRECT', 'FINAL,PROXY']);
});

test('Domestic core apps and AI precede ads; OpenAI retains proxy priority', () => {
  const advertising = index(ruleSet('Advertising', 'REJECT'));
  for (const name of ['WeChat', 'Zhihu', 'DouYin']) {
    assert.ok(index(ruleSet(name, 'DIRECT')) < advertising);
  }
  for (const domain of ['deepseek.com', 'kimi.com', 'moonshot.cn', 'fanqienovel.com']) {
    assert.ok(index(`DOMAIN-SUFFIX,${domain},DIRECT`) < advertising);
  }
  for (const domain of ['openai.com', 'chatgpt.com', 'chat.com', 'sora.com', 'oaistatic.com', 'oaiusercontent.com', 'chatgpt.livekit.cloud']) {
    assert.ok(index(`DOMAIN-SUFFIX,${domain},PROXY`) < advertising);
  }
  assert.ok(index('DOMAIN,challenges.cloudflare.com,PROXY') < advertising);
  assert.ok(index(ruleSet('DouYin', 'DIRECT')) < index(ruleSet('TikTok', 'PROXY')));
});

test('Steam download exceptions and AI exceptions precede broader rules', () => {
  assert.ok(index(ruleSet('SteamCN', 'DIRECT')) < index(ruleSet('Game', 'PROXY')));
  const lastAI = index(aiSupplement);
  for (const network of ['17.0.0.0/8', '2620:149::/32', '2403:300::/32', '2a01:b740::/32']) {
    assert.ok(index(`IP-CIDR,${network},DIRECT,no-resolve`) > lastAI);
  }
  assert.ok(index(ruleSet('Global', 'PROXY')) < index(ruleSet('China', 'DIRECT')));
});

test('LAN addresses avoid early DNS and retain a resolving fallback near FINAL', () => {
  const firstRemote = index(ruleSet('Lan', 'DIRECT'));
  const lastRemote = index(ruleSet('China', 'DIRECT'));
  const geoIP = index('GEOIP,CN,DIRECT');
  for (const network of ['127.0.0.0/8', '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16', '100.64.0.0/10', '169.254.0.0/16', '::1/128', 'fc00::/7', 'fe80::/10']) {
    assert.ok(index(`IP-CIDR,${network},DIRECT,no-resolve`) < firstRemote);
    const fallback = index(`IP-CIDR,${network},DIRECT`);
    assert.ok(fallback > lastRemote && fallback < geoIP);
  }
});

test('URL rewrites are restricted to Google China entry-point redirects', () => {
  assert.deepEqual(sections.get('URL Rewrite'), [
    "'^https?://(www\\.)?google\\.cn($|/.*)' 'https://www.google.com$2' 302",
    "'^https?://(www\\.)?g\\.cn($|/.*)' 'https://www.google.com$2' 302",
  ]);
});

test('Merlin public domain lists are valid, unique and non-overlapping', () => {
  const direct = lines(read('../../merlin/direct-domains.txt'));
  const proxy = lines(read('../../merlin/proxy-domains.txt'));
  assert.equal(direct.length, 119);
  assert.equal(proxy.length, 49);
  for (const values of [direct, proxy]) {
    assert.equal(new Set(values).size, values.length);
    for (const value of values) {
      assert.equal(value, value.toLowerCase());
      assert.ok(value.length <= 253 && !isIP(value));
      const labels = value.split('.');
      assert.ok(labels.length >= 2 && /^[a-z][a-z0-9-]*$/.test(labels.at(-1)));
      assert.ok(labels.every((label) => /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(label)));
    }
  }
  assert.deepEqual(direct.filter((domain) => proxy.includes(domain)), []);
});
