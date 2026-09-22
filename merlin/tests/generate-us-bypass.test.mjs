import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, readFile, stat, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { generateBypass, parseBackup, parseArgs, runCli, writeOutputs, createLookup, OUTPUT_FILES } from '../scripts/generate-us-bypass.mjs';

const encode = (text) => Buffer.from(text).toString('base64');
const backup = (nodes, domains = '', ips = '') => ({
  nodes,
  global: { ss_wan_white_domain: encode(domains), ss_wan_white_ip: encode(ips), subscription: 'SECRET_SUBSCRIPTION' },
  irrelevantSecret: 'SECRET_TOP_LEVEL',
});
const node = (name = '美国 测试', server = 'edge.example.test') => ({ name, server, port: '443', password: 'SECRET_PASSWORD', xray_uuid: 'SECRET_UUID' });
const answer = (ipv4 = ['192.0.2.1'], ipv6 = []) => ({ ipv4, ipv6 });

test('20 nodes / 11 IPv4 addresses, preserving existing entries and AAAA locally', async () => {
  const nodes = Array.from({ length: 20 }, (_, index) => node(`美国 A${String(index + 1).padStart(2, '0')}`, `edge${index + 1}.example.test`));
  nodes.push(node('日本 测试', 'other.example.test'));
  const result = await generateBypass(backup(nodes, 'direct.example.test\nedge1.example.test', '192.0.2.1/32'), {
    lookup: async (server) => {
      const number = Number(server.match(/^edge(\d+)/)[1]);
      return answer([`192.0.2.${((number - 1) % 11) + 1}`], ['2001:db8::1']);
    },
  });
  assert.equal(result.summary.matchedNodes, 20);
  assert.equal(result.summary.uniqueEndpoints, 20);
  assert.equal(result.summary.totalDomains, 21);
  assert.equal(result.summary.addedDomains, 19);
  assert.equal(result.summary.totalIPv4Rules, 11);
  assert.equal(result.summary.addedIPv4Rules, 10);
  assert.equal(result.summary.ipv6Endpoints, 20);
  assert.equal(result.domains[0], 'direct.example.test');
  assert.equal(result.ips[0], '192.0.2.1/32');
  assert.ok(result.ips.every((rule) => /^192\.0\.2\.\d+\/32$/.test(rule)));
  assert.deepEqual(result.nodes[0].ipv6, ['2001:db8::1']);
  assert.doesNotMatch(JSON.stringify(result), /SECRET_|password|xray_uuid|subscription/);
});

test('zero matches fails without performing DNS', async () => {
  await assert.rejects(generateBypass(backup([node('日本 测试')]), { lookup: () => { assert.fail('DNS must not run'); } }), { code: 'NO_MATCH' });
});

test('duplicate domains are queried once and matching can be overridden', async () => {
  let calls = 0;
  const result = await generateBypass(backup([node('区域X A', 'EDGE.EXAMPLE.TEST.'), node('区域X B')]), {
    match: '区域X', lookup: async () => { calls++; return answer(['192.0.2.1', '192.0.2.1']); },
  });
  assert.equal(calls, 1);
  assert.equal(result.summary.matchedNodes, 2);
  assert.equal(result.summary.uniqueEndpoints, 1);
  assert.deepEqual(result.domains, ['edge.example.test']);
  assert.deepEqual(result.ips, ['192.0.2.1/32']);
});

test('literal IPv4 bypasses DNS; IPv6-only fails instead of entering IPv4 whitelist', async () => {
  const never = () => { assert.fail('literal addresses must not use DNS'); };
  const result = await generateBypass(backup([node('美国 IP', '198.51.100.7')], 'keep.example.test', '203.0.113.9'), { lookup: never });
  assert.deepEqual(result.domains, ['keep.example.test']);
  assert.deepEqual(result.ips, ['203.0.113.9/32', '198.51.100.7/32']);
  await assert.rejects(generateBypass(backup([node('美国 IPv6', '2001:db8::7')]), { lookup: never }), { code: 'NO_IPV4' });
});

test('any unresolved endpoint fails; arbitrary DNS errors are not reflected', async () => {
  await assert.rejects(generateBypass(backup([node(), node('美国 B', 'missing.example.test')]), {
    lookup: async (server) => {
      if (server.startsWith('missing')) throw new Error('SECRET_DNS_TRACE');
      return answer();
    },
  }), (error) => error.code === 'NO_IPV4' && !error.message.includes('SECRET'));
  await assert.rejects(generateBypass(backup([node()]), { lookup: async () => answer([], ['2001:db8::1']) }), { code: 'NO_IPV4' });
  await assert.rejects(generateBypass(backup([node()]), { lookup: async () => answer(['not-an-ip']) }), { code: 'INVALID_DNS_ANSWER' });
});

test('malformed backup/base64/port and broad IPv4/IPv6 allowlists fail safely', () => {
  assert.throws(() => parseBackup({ nodes: {} }), { code: 'INVALID_BACKUP' });
  const invalid = backup([node()]);
  invalid.global.ss_wan_white_domain = '%SECRET%';
  assert.throws(() => parseBackup(invalid), { code: 'INVALID_BASE64' });
  assert.throws(() => parseBackup(backup([{ ...node(), port: '443 SECRET' }])), { code: 'INVALID_PORT' });
  assert.throws(() => parseBackup(backup([node()], '', '192.0.2.0/24')), { code: 'UNSAFE_IP_RULE' });
  assert.throws(() => parseBackup(backup([node()], '', '2001:db8::/32')), { code: 'UNSAFE_IP_RULE' });
  assert.throws(() => parseBackup(backup([node('美国', 'https://SECRET@edge.example.test')])), { code: 'INVALID_DOMAIN' });
});

test('CLI flags require explicit output or dry-run; resolver flags can repeat', () => {
  assert.throws(() => parseArgs(['--backup', 'input.json']), { code: 'MISSING_ARGUMENT' });
  assert.throws(() => parseArgs(['--backup', 'input.json', '--dry-run', '--resolver', 'dns.example.test']), { code: 'INVALID_RESOLVER' });
  const parsed = parseArgs(['--backup', 'input.json', '--dry-run', '--resolver', '192.0.2.53', '--resolver', '2001:db8::53']);
  assert.deepEqual(parsed.resolvers, ['192.0.2.53', '2001:db8::53']);
});

test('multiple resolvers union A/AAAA answers without exposing raw DNS errors', async () => {
  const selected = [];
  const lookup = createLookup(['192.0.2.53', '198.51.100.53', '192.0.2.53'], {
    resolverFactory: () => {
      let address;
      return {
        setServers: ([value]) => { address = value; selected.push(value); },
        resolve4: async () => address === '192.0.2.53' ? ['192.0.2.1', '192.0.2.2'] : ['192.0.2.2', '192.0.2.3'],
        resolve6: async () => {
          if (address === '198.51.100.53') throw Object.assign(new Error('SECRET_DNS_DETAIL'), { code: 'ENODATA' });
          return ['2001:db8::1'];
        },
      };
    },
  });
  assert.deepEqual(selected, ['192.0.2.53', '198.51.100.53']);
  assert.deepEqual(await lookup('edge.example.test'), { ipv4: ['192.0.2.1', '192.0.2.2', '192.0.2.3'], ipv6: ['2001:db8::1'], failedQueries: 0 });
});

async function temporary(testContext) {
  const directory = await mkdtemp(join(tmpdir(), 'us-bypass-test-'));
  testContext.after(() => rm(directory, { recursive: true, force: true }));
  return directory;
}

test('dry-run writes nothing and never logs endpoints, node names or secrets', async (t) => {
  const directory = await temporary(t);
  const input = join(directory, 'backup.json');
  const output = join(directory, 'new-output');
  await writeFile(input, JSON.stringify(backup([node('美国 PRIVATE_NAME')])));
  const logs = [], errors = [];
  const code = await runCli(['--backup', input, '--dry-run', '--output', output], {
    lookup: async () => answer(), stdout: (text) => logs.push(text), stderr: (text) => errors.push(text),
  });
  assert.equal(code, 0);
  assert.deepEqual(errors, []);
  assert.doesNotMatch(logs.join(''), /SECRET|PRIVATE_NAME|edge\.example|192\.0\.2/);
  assert.equal(JSON.parse(logs[0]).matchedNodes, 1);
  assert.deepEqual(await readdir(directory), ['backup.json']);
});

test('CLI success writes private files and refuses to overwrite an existing good set', async (t) => {
  const directory = await temporary(t);
  const input = join(directory, 'backup.json');
  const output = join(directory, 'private-output');
  await writeFile(input, JSON.stringify(backup([node()])));
  const options = { lookup: async () => answer(), stdout: () => {}, stderr: () => {} };
  assert.equal(await runCli(['--backup', input, '--output', output], options), 0);
  assert.deepEqual((await readdir(output)).sort(), [...OUTPUT_FILES].sort());
  for (const filename of OUTPUT_FILES) {
    assert.equal((await stat(join(output, filename))).mode & 0o777, 0o600);
    assert.doesNotMatch(await readFile(join(output, filename), 'utf8'), /SECRET_|password|xray_uuid|subscription/);
  }
  assert.equal((await stat(output)).mode & 0o777, 0o700);
  const before = await readFile(join(output, OUTPUT_FILES[1]), 'utf8');
  assert.equal(await runCli(['--backup', input, '--output', output], { ...options, lookup: async () => answer(['192.0.2.99']) }), 1);
  assert.equal(await readFile(join(output, OUTPUT_FILES[1]), 'utf8'), before);
});

test('failed resolution and invalid JSON neither overwrite lists nor leak input', async (t) => {
  const directory = await temporary(t);
  const input = join(directory, 'backup.json');
  const output = join(directory, 'private-output');
  const good = await generateBypass(backup([node()]), { lookup: async () => answer() });
  await writeOutputs(output, good);
  const before = await Promise.all(OUTPUT_FILES.map((filename) => readFile(join(output, filename), 'utf8')));
  await writeFile(input, JSON.stringify(backup([node()])));
  const errors = [];
  const options = { lookup: async () => { throw new Error('SECRET_DNS_TRACE'); }, stdout: () => assert.fail('failure must not print results'), stderr: (text) => errors.push(text) };
  assert.equal(await runCli(['--backup', input, '--output', output], options), 1);
  await writeFile(input, '{"SECRET_INVALID_JSON":');
  assert.equal(await runCli(['--backup', input, '--output', output], options), 1);
  assert.doesNotMatch(errors.join(''), /SECRET|edge\.example/);
  assert.deepEqual(await Promise.all(OUTPUT_FILES.map((filename) => readFile(join(output, filename), 'utf8'))), before);
});

test('Fake-IP A plus mapped AAAA fails without creating output or changing good files', async (t) => {
  const directory = await temporary(t);
  const input = join(directory, 'backup.json');
  const output = join(directory, 'private-output');
  const fresh = join(directory, 'must-not-exist');
  const good = await generateBypass(backup([node()]), { lookup: async () => answer() });
  await writeOutputs(output, good);
  const before = await Promise.all(OUTPUT_FILES.map((filename) => readFile(join(output, filename), 'utf8')));
  await writeFile(input, JSON.stringify(backup([node()])));
  const errors = [];
  const options = {
    lookup: async () => answer(['198.18.0.33'], ['::ffff:198.18.0.33']),
    stdout: () => assert.fail('unsafe response must not print results'),
    stderr: (text) => errors.push(text),
  };
  assert.equal(await runCli(['--backup', input, '--output', output], options), 1);
  assert.equal(await runCli(['--backup', input, '--output', fresh], options), 1);
  assert.equal(await runCli(['--backup', input, '--dry-run'], options), 1);
  assert.match(errors[0], /Fake-IP.*可信真实 DNS/);
  assert.doesNotMatch(errors.join(''), /198\.18\.0\.33|edge\.example|SECRET/);
  await assert.rejects(stat(fresh), { code: 'ENOENT' });
  assert.deepEqual(await Promise.all(OUTPUT_FILES.map((filename) => readFile(join(output, filename), 'utf8'))), before);
});

test('new resolved or literal special-use IPv4 addresses are rejected', async () => {
  const rejected = ['0.1.2.3', '10.1.2.3', '100.64.0.1', '100.127.255.254', '127.0.0.1', '169.254.1.2',
    '172.16.1.1', '172.31.255.254', '192.168.1.1', '198.18.0.1', '198.19.255.254', '224.0.0.1', '240.0.0.1', '255.255.255.255'];
  for (const ip of rejected) {
    await assert.rejects(generateBypass(backup([node()]), { lookup: async () => answer([ip]) }), { code: 'UNSAFE_ENDPOINT_IP' });
    await assert.rejects(generateBypass(backup([node('美国 测试', ip)])), { code: 'UNSAFE_ENDPOINT_IP' });
  }
});

test('mapped unsafe AAAA is rejected even when A is otherwise acceptable', async () => {
  for (const mapped of ['::ffff:198.18.0.33', '::ffff:c612:21', '0:0:0:0:0:ffff:c613:ffff', '::ffff:10.0.0.1']) {
    await assert.rejects(generateBypass(backup([node()]), { lookup: async () => answer(['192.0.2.1'], [mapped]) }), { code: 'UNSAFE_ENDPOINT_IP' });
  }
});

test('existing Fake-IP whitelist fails, but old private host rules and documentation fixtures remain intact', async () => {
  assert.throws(() => parseBackup(backup([node()], '', '198.18.0.33/32')), { code: 'UNSAFE_ENDPOINT_IP' });
  assert.throws(() => parseBackup(backup([node()], '', '198.19.0.33')), { code: 'UNSAFE_ENDPOINT_IP' });
  const result = await generateBypass(backup([node()], '', '10.0.0.1/32\n192.168.1.1/32'), {
    lookup: async () => answer(['192.0.2.1', '198.51.100.1', '203.0.113.1']),
  });
  assert.deepEqual(result.ips, ['10.0.0.1/32', '192.168.1.1/32', '192.0.2.1/32', '198.51.100.1/32', '203.0.113.1/32']);
});
