import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
import { request } from 'node:http';
const root = resolve(process.argv[2]);
const { configuration } = await import(pathToFileURL(resolve(root, 'src/config.mjs')));
const { Harness } = await import(pathToFileURL(resolve(root, 'src/harness.mjs')));
const config = configuration();
const credential = await new Harness(config).cookie();
const rpcId = 'harmony-deployment-preflight';
const response = await new Promise((resolveResponse, reject) => {
  const req = request(new URL('/api/session/list', config.upstream), { method: 'POST', timeout: 15000,
    headers: { host: config.publicUrl.host, origin: config.publicUrl.origin, cookie: credential, 'content-type': 'application/json' } }, res => {
    const chunks = []; res.on('data', chunk => chunks.push(chunk));
    res.on('end', () => resolveResponse({ status: res.statusCode, body: Buffer.concat(chunks).toString() }));
  });
  req.on('error', reject); req.on('timeout', () => req.destroy());
  req.end(JSON.stringify({ type: 'client-request', rpcId, method: 'session/list', payload: { args: { _request: {} } } }));
});
if (response.status !== 200) throw Error('Harness preflight HTTP rejected: ' + response.status);
const result = JSON.parse(response.body);
if (result.result?.ok !== true || !Array.isArray(result.result.value?.items)) throw Error('Harness preflight contract mismatch');
console.log(JSON.stringify({ harnessReachable: true, sessions: result.result.value.items.length, running: result.result.value.items.filter(x => x.running).length }));
