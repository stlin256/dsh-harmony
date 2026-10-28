/** Check the actual Harness-served browser artifact, without logging HTML or credentials. */
import { readFile } from 'node:fs/promises';
import { runInNewContext } from 'node:vm';
const launch = new URL((await readFile(process.argv[2], 'utf8')).trim());
const response = await fetch(launch, { redirect: 'manual', signal: AbortSignal.timeout(10000) });
const cookie = response.headers.getSetCookie().map(x => x.split(';')[0]).join('; ');
if (response.status !== 303 || !cookie) throw Error('Harness credential exchange failed');
const index = await fetch(launch.origin + '/', { headers: { Cookie: cookie }, signal: AbortSignal.timeout(10000) });
if (!index.ok) throw Error('Harness index rejected');
const html = await index.text();
const urls = [...html.matchAll(/(?:src|href)=["']([^"']*plugins\/\?\?[^"']+)["']/g)].map(x => x[1].replaceAll('&amp;', '&'));
const path = urls.find(x => decodeURIComponent(x).includes('@dsh-harmony/plugin/client.js'));
if (!path) throw Error('Harmony client missing from Harness boot graph');
const code = await fetch(new URL(path, launch.origin + '/'), { headers: { Cookie: cookie }, signal: AbortSignal.timeout(10000) });
if (!code.ok) throw Error('Harness browser bundle rejected: ' + code.status);
const entries = [];
const opened = [];
const window = { __ModuleLoader__: { load: value => entries.push(value) },
  location: { href: 'https://workspace.example.com/?dshHarmonySession=probe' }, history: { state: {}, replaceState() {} } };
runInNewContext(await code.text(), { window, URL, console }, { timeout: 5000 });
const client = entries.find(x => x.id === '@dsh-harmony/plugin');
if (!client) throw Error('Browser bundle did not register the Harmony factory');
const exported = client.factory(() => { throw Error('Unexpected external dependency'); });
exported.apply({ uiWorkspace: { openSession: id => opened.push(id) } });
if (opened[0] !== 'probe') throw Error('Browser handoff failed');
console.log(JSON.stringify({ webModule: true, factoryRegistered: true, navigation: true }));
