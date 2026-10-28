import { test } from 'node:test';
import assert from 'node:assert/strict';
import { apply, consumeSession } from '../../plugins/harmony-navigation/client.mjs';
import { readFile } from 'node:fs/promises';
import { runInNewContext } from 'node:vm';

test('published browser entries register factories with the real Harness module-loader contract', async () => {
  for (const name of ['dsh-harmony', 'harmony-navigation']) {
    const root = new URL('../../plugins/' + name + '/', import.meta.url);
    const pkg = JSON.parse(await readFile(new URL('package.json', root)));
    const source = await readFile(new URL(pkg.exports['./client'], root), 'utf8');
    let registration;
    const selected = [];
    const window = { __ModuleLoader__: { load: value => { registration = value; } },
      location: { href: 'https://dsh.example.com/?dshHarmonySession=chosen' }, history: { state: {}, replaceState() {} } };
    runInNewContext(source, { window, URL });
    assert.equal(registration.id, pkg.name);
    const client = registration.factory(() => { throw Error('Unexpected import'); });
    client.apply({ uiWorkspace: { openSession: id => selected.push(id) } });
    assert.deepEqual(selected, ['chosen']);
    assert.equal(/^\s*(?:import|export)\s/m.test(source), false);
  }
});

test('compatibility handoff uses public workspace navigation and preserves other URL state', () => {
  const previous=globalThis.window;
  const selected=[],replaced=[];
  globalThis.window={location:{href:'https://dsh.example.com/?dshHarmonySession=session_1&layout=wide#panel'},history:{state:{tab:1},replaceState:(...args)=>replaced.push(args)}};
  try {
    apply({uiWorkspace:{openSession:id=>selected.push(id)}});
    assert.deepEqual(selected,['session_1']);
    assert.deepEqual(replaced,[[{tab:1},'','/?layout=wide#panel']]);
    assert.equal(consumeSession(new URL('https://dsh.example.com/?dshHarmonySession=..%2Fother')),'');
  } finally {globalThis.window=previous;}
});
