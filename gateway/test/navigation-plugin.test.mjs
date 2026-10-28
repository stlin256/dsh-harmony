import { test } from 'node:test';
import assert from 'node:assert/strict';
import { apply, consumeSession } from '../../plugins/harmony-navigation/client.mjs';

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
