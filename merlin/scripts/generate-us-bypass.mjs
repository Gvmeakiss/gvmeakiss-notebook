#!/usr/bin/env node
/**
 * Node.js 20+; no external packages. This tool does NOT modify a router.
 * Backups and generated endpoint lists are private: never commit them.
 */
import { Resolver } from 'node:dns/promises';
import { isIP } from 'node:net';
import { domainToASCII, pathToFileURL } from 'node:url';
import { resolve, join } from 'node:path';
import { readFile, mkdir, lstat, open, unlink } from 'node:fs/promises';

export const OUTPUT_FILES = [
  'merlin-direct-domains.txt',
  'merlin-direct-ips.txt',
  'us-node-endpoints.json',
];

export class SafeError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

const fail = (code, message) => { throw new SafeError(code, message); };
const unique = (values) => [...new Set(values)];
const isRecord = (value) => value !== null && typeof value === 'object' && !Array.isArray(value);

function isFakeIPv4(value) {
  const [first, second] = value.split('.').map(Number);
  return first === 198 && (second === 18 || second === 19);
}

// Deliberately a narrow safety check, not a complete IANA public-address registry.
// RFC documentation ranges remain usable by the offline test fixtures.
function unsafeEndpointIPv4(value) {
  const [first, second] = value.split('.').map(Number);
  return first === 0 || first === 10 || first === 127 || first >= 224
    || (first === 100 && second >= 64 && second <= 127)
    || (first === 169 && second === 254)
    || (first === 172 && second >= 16 && second <= 31)
    || (first === 192 && second === 168)
    || isFakeIPv4(value);
}

function mappedIPv4(value) {
  if (isIP(value) !== 6) return null;
  let address = value.toLowerCase();
  if (address.includes('.')) {
    const separator = address.lastIndexOf(':');
    const bytes = address.slice(separator + 1).split('.').map(Number);
    address = `${address.slice(0, separator + 1)}${((bytes[0] << 8) | bytes[1]).toString(16)}:${((bytes[2] << 8) | bytes[3]).toString(16)}`;
  }
  const [left, right] = address.split('::');
  const start = left ? left.split(':') : [];
  const end = right ? right.split(':') : [];
  const groups = right === undefined ? start : [...start, ...Array(8 - start.length - end.length).fill('0'), ...end];
  const words = groups.map((group) => Number.parseInt(group, 16));
  if (words.length !== 8 || words.slice(0, 5).some((word) => word !== 0) || words[5] !== 0xffff) return null;
  return [words[6] >> 8, words[6] & 255, words[7] >> 8, words[7] & 255].join('.');
}

function failUnsafeAddress() {
  fail('UNSAFE_ENDPOINT_IP', '检测到可能为客户端 Fake-IP 或本地地址的节点入口；关闭客户端虚拟 DNS 后或选择可信真实 DNS 重新解析。未写入任何输出。');
}

function domain(value) {
  if (typeof value !== 'string' || value !== value.trim()) {
    fail('INVALID_DOMAIN', '存在格式不正确的域名。');
  }
  const result = domainToASCII(value.replace(/\.$/, '')).toLowerCase();
  if (!result || result.length > 253 || !result.includes('.') || isIP(result)
      || !result.split('.').every((label) => /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(label))) {
    fail('INVALID_DOMAIN', '存在格式不正确的域名。');
  }
  return result;
}

function endpoint(value) {
  if (typeof value !== 'string' || value !== value.trim() || !value) {
    fail('INVALID_ENDPOINT', '匹配节点的入口格式不正确。');
  }
  return isIP(value) ? value : domain(value);
}

function decodeList(value) {
  if (value === undefined || value === '') return [];
  if (typeof value !== 'string') fail('INVALID_BASE64', '白名单字段必须为 Base64 字符串。');
  const encoded = value.replace(/[\r\n\t ]/g, '');
  if (!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(encoded)) {
    fail('INVALID_BASE64', '白名单字段不是有效的 Base64。');
  }
  let decoded;
  try {
    const bytes = Buffer.from(encoded, 'base64');
    if (bytes.toString('base64') !== encoded) throw new Error();
    decoded = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } catch {
    fail('INVALID_BASE64', '白名单字段不是有效的 UTF-8 Base64。');
  }
  return decoded.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
}

function ipv4HostRule(value) {
  const parts = value.split('/');
  if (parts.length > 2 || isIP(parts[0]) !== 4 || (parts.length === 2 && parts[1] !== '32')) {
    fail('UNSAFE_IP_RULE', '原 IP 白名单含非单个 IPv4 或非 /32 条目；请先人工审阅，工具不会扩大绕过网段。');
  }
  if (isFakeIPv4(parts[0])) failUnsafeAddress();
  return `${parts[0]}/32`;
}

/** Project only the allowlist and matched node fields; ignore all credentials. */
export function parseBackup(backup, match = '美国') {
  if (!isRecord(backup) || !Array.isArray(backup.nodes) || !isRecord(backup.global)
      || typeof match !== 'string' || !match.trim()) {
    fail('INVALID_BACKUP', '需要 fancyss 新版 JSON 备份（nodes 数组与 global 对象）。');
  }
  const nodes = [];
  for (const item of backup.nodes) {
    if (!isRecord(item) || typeof item.name !== 'string') {
      fail('INVALID_NODE', '备份中的节点格式不正确。');
    }
    if (!item.name.includes(match)) continue;
    if (!/^(?:\d{1,5})$/.test(String(item.port)) || Number(item.port) < 1 || Number(item.port) > 65535) {
      fail('INVALID_PORT', '匹配节点的端口格式不正确。');
    }
    nodes.push({ name: item.name, server: endpoint(item.server), port: Number(item.port) });
  }
  if (!nodes.length) fail('NO_MATCH', '没有匹配节点；未写入任何输出。');
  return {
    nodes,
    domains: unique(decodeList(backup.global.ss_wan_white_domain).map(domain)),
    ips: unique(decodeList(backup.global.ss_wan_white_ip).map(ipv4HostRule)),
  };
}

/** Query every supplied resolver, unioning answers. With none, use system DNS. */
export function createLookup(resolvers = [], { resolverFactory = () => new Resolver({ timeout: 3000, tries: 1 }) } = {}) {
  if (resolvers.some((address) => !isIP(address))) fail('INVALID_RESOLVER', '--resolver 仅接受 DNS 服务器的 IP 地址。');
  const clients = (resolvers.length ? unique(resolvers) : [null]).map((address) => {
    const client = resolverFactory();
    if (address) client.setServers([address]);
    return client;
  });
  return async (server) => {
    const answers = await Promise.all(clients.map(async (client) => {
      const [a, aaaa] = await Promise.allSettled([client.resolve4(server), client.resolve6(server)]);
      // A missing AAAA record is ordinary, not a reason to discard valid A records.
      const unexpected = (result) => result.status === 'rejected'
        && !['ENODATA', 'ENOTFOUND'].includes(result.reason?.code);
      return {
        ipv4: a.status === 'fulfilled' ? a.value : [],
        ipv6: aaaa.status === 'fulfilled' ? aaaa.value : [],
        failedQueries: Number(a.status === 'rejected') + Number(unexpected(aaaa)),
      };
    }));
    return {
      ipv4: unique(answers.flatMap((answer) => answer.ipv4)),
      ipv6: unique(answers.flatMap((answer) => answer.ipv6)),
      failedQueries: answers.reduce((sum, answer) => sum + answer.failedQueries, 0),
    };
  };
}

async function mapLimited(items, task, limit = 4) {
  const result = new Array(items.length);
  let next = 0;
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length) {
      const index = next++;
      result[index] = await task(items[index]);
    }
  }));
  return result;
}

/** Pure except for the injected lookup; failures happen before any file writes. */
export async function generateBypass(backup, { match = '美国', lookup = createLookup() } = {}) {
  const input = parseBackup(backup, match);
  const servers = unique(input.nodes.map((node) => node.server));
  const endpoints = await mapLimited(servers, async (server) => {
    let answer;
    if (isIP(server) === 4) answer = { ipv4: [server], ipv6: [] };
    else if (isIP(server) === 6) answer = { ipv4: [], ipv6: [server] };
    else {
      try { answer = await lookup(server); }
      catch { answer = { ipv4: [], ipv6: [], failedQueries: 1 }; }
    }
    if (!answer || !Array.isArray(answer.ipv4) || !Array.isArray(answer.ipv6)
        || answer.ipv4.some((ip) => isIP(ip) !== 4) || answer.ipv6.some((ip) => isIP(ip) !== 6)) {
      fail('INVALID_DNS_ANSWER', 'DNS 返回了格式不正确的地址；未写入任何输出。');
    }
    if (answer.ipv4.some(unsafeEndpointIPv4)
        || answer.ipv6.some((ip) => { const mapped = mappedIPv4(ip); return mapped !== null && unsafeEndpointIPv4(mapped); })) {
      failUnsafeAddress();
    }
    return { server, ipv4: unique(answer.ipv4), ipv6: unique(answer.ipv6), failedQueries: Number(answer.failedQueries) || 0 };
  });
  const missing = endpoints.filter((item) => !item.ipv4.length).length;
  if (missing) fail('NO_IPV4', `有 ${missing} 个入口未获得 IPv4；未写入任何输出。IPv6-only 入口需另行核验路由策略。`);
  const domains = unique([...input.domains, ...servers.filter((server) => !isIP(server))]);
  const ips = unique([...input.ips, ...endpoints.flatMap((item) => item.ipv4.map((ip) => `${ip}/32`))]);
  const byServer = new Map(endpoints.map((item) => [item.server, item]));
  const failedQueries = endpoints.reduce((sum, item) => sum + item.failedQueries, 0);
  const ipv6Endpoints = endpoints.filter((item) => item.ipv6.length).length;
  const warnings = [];
  if (failedQueries) warnings.push('部分 DNS 查询失败；已合并其他成功响应。应用前请核验当前网络解析结果。');
  if (ipv6Endpoints) warnings.push('AAAA 仅记录于本地映射，不写入 IPv4 名单；本工具不修改 IPv6 代理策略。');
  warnings.push('结果仅覆盖本次备份与本次 DNS 快照；订阅或入口地址变动后需重新生成。');
  return {
    domains, ips, endpoints,
    nodes: input.nodes.map((node) => ({ ...node, ipv4: byServer.get(node.server).ipv4, ipv6: byServer.get(node.server).ipv6 })),
    summary: {
      matchedNodes: input.nodes.length,
      uniqueEndpoints: endpoints.length,
      totalDomains: domains.length,
      addedDomains: domains.length - input.domains.length,
      totalIPv4Rules: ips.length,
      addedIPv4Rules: ips.length - input.ips.length,
      ipv6Endpoints,
      failedQueries,
      warnings,
    },
  };
}

/** Refuse to overwrite an earlier output set. Use a fresh private subdirectory. */
export async function writeOutputs(outputDirectory, result) {
  const directory = resolve(outputDirectory);
  try {
    const info = await lstat(directory);
    if (!info.isDirectory() || info.isSymbolicLink()) fail('UNSAFE_OUTPUT', '输出位置必须是普通目录，不能是符号链接。');
  } catch (error) {
    if (error instanceof SafeError) throw error;
    if (error.code !== 'ENOENT') fail('OUTPUT_CHECK_FAILED', '无法检查输出目录。');
  }
  for (const filename of OUTPUT_FILES) {
    try {
      await lstat(join(directory, filename));
      fail('OUTPUT_EXISTS', '输出文件已经存在；请选择新的 private-output 子目录，旧清单不会被覆盖。');
    } catch (error) {
      if (error instanceof SafeError) throw error;
      if (error.code !== 'ENOENT') fail('OUTPUT_CHECK_FAILED', '无法检查输出文件。');
    }
  }
  const content = [
    `${result.domains.join('\n')}\n`,
    `${result.ips.join('\n')}\n`,
    `${JSON.stringify({ format: 'fancyss-us-bypass-v1', generatedAt: new Date().toISOString(),
      summary: result.summary, nodes: result.nodes, endpoints: result.endpoints }, null, 2)}\n`,
  ];
  const created = [];
  try {
    await mkdir(directory, { recursive: true, mode: 0o700 });
    for (let index = 0; index < OUTPUT_FILES.length; index++) {
      const path = join(directory, OUTPUT_FILES[index]);
      const handle = await open(path, 'wx', 0o600);
      created.push(path);
      try { await handle.writeFile(content[index]); }
      finally { await handle.close(); }
    }
  } catch {
    // Only remove exact files created by this invocation, never pre-existing files.
    await Promise.all(created.map((path) => unlink(path).catch(() => {})));
    fail('WRITE_FAILED', '无法安全写入全部输出；请使用新的、可写的私有目录。');
  }
}

export const HELP = `用法（Node.js 20+）：
  node merlin/scripts/generate-us-bypass.mjs --backup PATH --dry-run
  node merlin/scripts/generate-us-bypass.mjs --backup PATH --output ./private-output/us-bypass-run

选项：
  --backup PATH    fancyss 新版 JSON 备份；仅在本机读取，备份通常包含凭据
  --match TEXT     节点名称包含此文字（非正则），默认：美国
  --resolver IP   使用指定 DNS 服务器，可重复指定并合并结果；默认系统 DNS
  --dry-run       只输出计数与警告，不写文件、不打印真实端点
  --output DIR    非 dry-run 必填；推荐每次选择新的 private-output 子目录
  --help          显示帮助

输出（权限 600；新建目录权限 700）：
  merlin-direct-domains.txt  合并原白名单与全部匹配节点的真实入口域名
  merlin-direct-ips.txt      合并原单个 IPv4 条目与入口 A 记录（仅 /32）
  us-node-endpoints.json    本地节点/入口/A/AAAA 映射；不包含订阅或认证字段

注意：不连接、不修改路由器或客户端；不覆盖已有输出。
无匹配、格式错误、任一匹配入口没有 IPv4 时失败并保留旧清单。
原 IP 白名单若含非 /32 网段或 IPv6 将拒绝处理，须先人工审阅。
新增入口拒绝常见 Fake-IP、私网、回环、链路本地、CGNAT 及组播/保留高位地址。
检测到这些地址时，请关闭客户端虚拟 DNS 或选择可信真实 DNS 后重新解析。
原名单中的 Fake-IP 同样拒绝；其他原有单个 IPv4 条目保留。
AAAA 仅记录，不写入 IPv4 名单；不能据此宣称 IPv6 已绕过。
订阅及 DNS 变化后需重跑。备份和生成名单都属于隐私数据，禁止提交 Git。
`;

export function parseArgs(argv) {
  const result = { resolvers: [], match: '美国', dryRun: false, help: false };
  const seen = new Set();
  const values = new Map([['--backup', 'backup'], ['--match', 'match'], ['--output', 'output'], ['--resolver', 'resolver']]);
  for (let index = 0; index < argv.length; index++) {
    const argument = argv[index];
    if (argument === '--help') { result.help = true; continue; }
    if (argument === '--dry-run') { result.dryRun = true; continue; }
    if (!values.has(argument) || !argv[index + 1] || argv[index + 1].startsWith('--')) {
      fail('INVALID_ARGUMENT', '参数不正确或缺少值；使用 --help 查看用法。');
    }
    if (argument !== '--resolver' && seen.has(argument)) fail('DUPLICATE_ARGUMENT', '同一选项不能重复指定（--resolver 除外）。');
    seen.add(argument);
    const value = argv[++index];
    if (argument === '--resolver') result.resolvers.push(value);
    else result[values.get(argument)] = value;
  }
  if (result.help) return result;
  if (!result.backup || (!result.dryRun && !result.output) || !result.match.trim()) {
    fail('MISSING_ARGUMENT', '请指定 --backup，并选择 --dry-run 或 --output DIR。');
  }
  if (result.resolvers.some((address) => !isIP(address))) fail('INVALID_RESOLVER', '--resolver 仅接受 DNS 服务器的 IP 地址。');
  return result;
}

export async function runCli(argv, { stdout = console.log, stderr = console.error, lookup } = {}) {
  try {
    const options = parseArgs(argv);
    if (options.help) { stdout(HELP); return 0; }
    let backup;
    try { backup = JSON.parse(await readFile(options.backup, 'utf8')); }
    catch { fail('READ_BACKUP_FAILED', '无法读取有效的 JSON 备份；请检查本地路径、权限和文件格式。'); }
    const result = await generateBypass(backup, { match: options.match, lookup: lookup ?? createLookup(options.resolvers) });
    if (!options.dryRun) await writeOutputs(options.output, result);
    stdout(JSON.stringify({ dryRun: options.dryRun, ...result.summary }, null, 2));
    return 0;
  } catch (error) {
    // Never echo arbitrary parser, filesystem, DNS, or backup-provided messages.
    stderr(error instanceof SafeError ? `${error.code}: ${error.message}` : 'UNEXPECTED_ERROR: 处理失败；未输出输入数据，请检查格式与本地环境。');
    return 1;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  process.exitCode = await runCli(process.argv.slice(2));
}
