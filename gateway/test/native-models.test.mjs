// Exercises service logic under kit mocks. This is not an ArkTS/Hvigor build.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import ts from 'typescript';

const services = new URL('../../harmony/entry/src/main/ets/services/', import.meta.url);
function load(name, kits, globals = {}) {
  const source = readFileSync(new URL(name + '.ets', services), 'utf8');
  const output = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS } });
  const module = { exports: {} };
  vm.runInNewContext(output.outputText, { module, exports: module.exports, require: id => {
    if (!(id in kits)) throw Error('Unexpected dependency: ' + id);
    return kits[id];
  }, ...globals });
  return module.exports;
}
function storage() {
  const disk = new Map();
  const preferences = {
    removePreferencesFromCacheSync() {},
    getPreferencesSync(_ctx, { name }) {
      if (!disk.has(name)) disk.set(name, new Map());
      const file = disk.get(name);
      return { getSync: (key, fallback) => structuredClone(file.has(key) ? file.get(key) : fallback),
        putSync: (key, value) => file.set(key, structuredClone(value)), flushSync() {} };
    }
  };
  return { disk, preferences };
}
const context = { getApplicationContext() { return this; } };

test('widget privacy defaults, cross-process restoration, expiry and logout serialization', async () => {
  const { preferences, disk } = storage();
  const deliveries = [];
  let block;
  let now = Date.now();
  class Clock extends Date { static now() { return now; } }
  const kits = { '@kit.AbilityKit': {}, '@kit.ArkData': { preferences }, '@kit.FormKit': {
    formBindingData: { createFormBindingData: data => ({ data }) }, formProvider: {
      async updateForm(id, value) { if (block) await block; deliveries.push({ id, value }); }
    }
  } };
  const { WidgetStore, OverviewSnapshot } = load('WidgetStore', kits, { Date: Clock });
  WidgetStore.register(context, '123');
  WidgetStore.register(context, '123');
  const snapshot = Object.assign(new OverviewSnapshot(), { running: 2, waiting: 1, completed: 3, failed: 0, observedAt: now, generatedAt: now });
  await WidgetStore.update(context, snapshot);
  assert.equal(WidgetStore.data(context).showCounts, false);
  assert.equal(disk.get('pocket-widget-snapshot').get('snapshot'), '');
  assert.equal(deliveries.length, 1, 'duplicate form instance IDs must not duplicate delivery');
  await WidgetStore.setDetails(context, true);
  await WidgetStore.update(context, snapshot);
  assert.equal(WidgetStore.data(context).showCounts, true);
  assert.equal(WidgetStore.data(context).running, '2');
  const restarted = load('WidgetStore', kits, { Date: Clock });
  assert.equal(restarted.WidgetStore.data(context).waiting, '1');
  now += 16 * 60000;
  assert.equal(WidgetStore.data(context).showCounts, false);
  assert.match(WidgetStore.data(context).detail, /过期/);
  let release;
  block = new Promise(resolve => { release = resolve; });
  const updating = WidgetStore.update(context, snapshot);
  const clearing = WidgetStore.clear(context);
  release(); block = null;
  await Promise.all([updating, clearing]);
  assert.equal(WidgetStore.data(context).headline, '连接工作空间');
  assert.equal(deliveries.at(-1).value.data.showCounts, false);
  assert.equal(disk.get('pocket-widget-snapshot').get('snapshot'), '');
  WidgetStore.remove(context, '123');
  const before = deliveries.length;
  await WidgetStore.update(context, snapshot);
  assert.equal(deliveries.length, before, 'removed form must not receive updates');
});

test('system material guards old runtimes and respects opacity, motion and power policies', () => {
  const { preferences } = storage();
  const state = new Map();
  const AppStorage = { get: key => state.get(key), setOrCreate: (key, value) => state.set(key, value) };
  const deviceInfo = { sdkApiVersion: 23 };
  const uiMaterial = { getMaterialInfo: () => ({ state: 0 }), MaterialState: { DISABLE: 2 }, Material: { empty: { disabled: true } },
    ImmersiveStyle: { THIN: 1 }, ImmersiveMaterial: class { constructor(options) {
      assert.ok(deviceInfo.sdkApiVersion >= 26, 'API-26 constructor reached on old device'); this.options = options;
    } } };
  const power = { getPowerMode: () => 600, DevicePowerMode: { MODE_NORMAL: 600, MODE_PERFORMANCE: 602 } };
  const kits = { '@kit.AbilityKit': {}, '@kit.ArkData': { preferences }, '@kit.BasicServicesKit': { deviceInfo, power },
    '@kit.AccessibilityKit': { accessibility: { isAnimationReduceEnabledSync: () => false } }, '@kit.ArkUI': { uiMaterial } };
  const { NativeExperience, ChromeMaterialModifier } = load('NativeExperience', kits, { AppStorage, canIUse: () => true, BarStyle: { STANDARD: 0 }, Color: { White: '#fff' } });
  NativeExperience.refresh(context);
  assert.equal(NativeExperience.materialsEnabled(), false);
  assert.equal(NativeExperience.titleOptions(false, 0).systemMaterial, undefined);
  let applied;
  new ChromeMaterialModifier(0).applyNormalAttribute({ systemMaterial: value => { applied = value; } });
  assert.equal(applied, undefined);
  deviceInfo.sdkApiVersion = 26;
  assert.equal(NativeExperience.materialsEnabled(), true);
  new ChromeMaterialModifier(1).applyNormalAttribute({ systemMaterial: value => { applied = value; } });
  assert.equal(applied.options.interactive, true);
  state.set('nativeSystemReduceMotion', true);
  new ChromeMaterialModifier(2).applyNormalAttribute({ systemMaterial: value => { applied = value; } });
  assert.equal(applied.options.interactive, false);
  assert.equal(applied.options.lightEffect, null);
  NativeExperience.setPreference(context, 'reduceTransparency', true);
  assert.equal(NativeExperience.materialsEnabled(), false);
  assert.equal(NativeExperience.titleOptions(false, 0).systemMaterial.disabled, true);
  NativeExperience.setPreference(context, 'reduceTransparency', false);
  state.set('nativePowerSaving', true);
  assert.equal(NativeExperience.materialsEnabled(), false);
  state.set('nativePowerSaving', false); state.set('nativeAppActive', false);
  assert.equal(NativeExperience.materialsEnabled(), false);
});

test('form metadata resolves actual static card pages and resources', () => {
  const base = new URL('../../harmony/entry/src/main/', import.meta.url);
  const manifest = JSON.parse(readFileSync(new URL('module.json5', base), 'utf8'));
  const forms = JSON.parse(readFileSync(new URL('resources/base/profile/form_config.json', base), 'utf8')).forms;
  assert.equal(manifest.module.extensionAbilities[0].type, 'form');
  assert.equal(manifest.module.abilities[0].launchType, 'singleton');
  assert.equal(forms.filter(form => form.isDefault).length, 1);
  assert.deepEqual(forms.map(form => form.defaultDimension), ['2*2', '2*4']);
  for (const form of forms) {
    assert.ok(form.supportDimensions.includes(form.defaultDimension));
    assert.equal(form.isDynamic, false);
    assert.ok(existsSync(fileURLToPath(new URL(form.src, base))));
    const source = readFileSync(new URL(form.src, base), 'utf8');
    assert.match(source, /FormLink/);
    assert.doesNotMatch(source, /fetch\(|Web\(|INTERNET|cookie|serverOrigin/);
  }
});

test('native session reducer restores streams, deduplicates replay and replaces history', () => {
  const {NativeSessionModel}=load('NativeSessionModel',{});
  const model=new NativeSessionModel();
  model.apply({type:'snapshot',cursor:1,messages:[{id:'event-1',seq:1,text:'old'}],hasMore:false,attemptId:'attempt',nextIndex:2,text:'hel',reasoning:''});
  model.apply({type:'delta',attemptId:'attempt',index:2,text:'lo',reasoning:''});
  model.apply({type:'delta',attemptId:'attempt',index:2,text:'DUPLICATE',reasoning:''});
  assert.equal(model.streamText,'hello');
  assert.throws(()=>model.apply({type:'delta',attemptId:'attempt',index:4,text:'gap'}));
  model.apply({type:'event',seq:2,replaceStart:1,replaceEnd:1,message:{id:'event-2',seq:2,text:'new'}});
  model.apply({type:'event',seq:2,replaceStart:-1,replaceEnd:-1,message:{id:'event-2',seq:2,text:'duplicate'}});
  assert.equal(model.messages.length,1);assert.equal(model.messages[0].text,'new');
  model.apply({type:'state',running:true,waiting:true});assert.equal(model.waiting,true);
  model.apply({type:'end',attemptId:'attempt'});assert.equal(model.streamText,'');
  model.prepend({messages:[{seq:0,id:'event-0',text:'older'},{seq:2,id:'event-2',text:'new'}],hasMore:false});
  assert.equal(model.messages.length,2);
});

test('native transport shares only gateway cookies, disables redirects and never retries prompts', async () => {
  const calls = [], configured = [];
  let code = 200, made = 0;
  let cookie = Promise.resolve('other=hidden; pocket=' + 'a'.repeat(43));
  const socketCallbacks = new Map();
  const socket = { on: (event, callback) => socketCallbacks.set(event, callback), off: event => socketCallbacks.delete(event),
    connect: async () => true, close: async () => true };
  const network = { http: { RequestMethod: { GET:'GET',POST:'POST' }, HttpDataType:{STRING:'string'}, createHttp:()=>({
    on(event, callback) { this[event] = callback; },
    async requestInStream(url, options) { calls.push({url,options}); const encoded = new TextEncoder().encode('{}'); this.dataReceive(encoded.buffer); this.dataEnd(); return code; },
    async request(url, options) { calls.push({url,options}); return {responseCode:code,header:{'set-cookie':'pocket='+'b'.repeat(43)+'; Path=/; Secure; HttpOnly'},result:'{}'}; }, destroy(){} }) },
    webSocket:{createWebSocket:()=>{made++;return socket;}} };
  const {NativeHarnessClient}=load('NativeHarnessClient',{
    '@kit.NetworkKit':network,'@kit.ArkWeb':{webview:{WebCookieManager:{fetchCookie:()=>cookie,configCookie:async(...args)=>configured.push(args),saveCookieAsync:async()=>{}}}},
    '@kit.ArkTS':{util:{generateRandomUUID:()=> 'request-id',TextDecoder:{create:()=>({decodeToString: buffer => new TextDecoder().decode(buffer)})}}},'@kit.BasicServicesKit':{},'./NativeSessionModel':{}
  });
  const client=new NativeHarnessClient('https://dsh.example.com');
  await client.request('/pocket/api/state');
  assert.equal(calls[0].options.header.Cookie,'pocket='+'a'.repeat(43));
  assert.equal(calls[0].options.maxRedirects,0);
  assert.equal(calls[0].options.extraData,undefined);
  assert.equal(configured.length,0,'ordinary responses must not overwrite the shared login cookie');
  await client.request('/pocket/api/auth/none','POST','{}');
  assert.equal(configured[0][2],false);assert.equal(configured[0][3],true);
  code=502;
  const before=calls.length;
  await assert.rejects(()=>client.prompt('session','hello'));
  assert.equal(calls.length,before+1,'a failed prompt must never be automatically replayed');
  assert.equal(client.uncertain.has('session'),true);
  code=401;
  await assert.rejects(()=>client.prompt('session','hello'));
  assert.equal(client.uncertain.has('session'),false,'a gateway authentication rejection never admitted the prompt');
  await assert.rejects(()=>client.request('/pocket/api/../../other'));
  let release;
  cookie=new Promise(resolve=>{release=resolve;});
  const pending=client.follow('session',()=>{},()=>{});
  client.pause();release('pocket='+'a'.repeat(43));await pending;
  assert.equal(made,0,'paused generation must not create a late socket');
  cookie=Promise.resolve('pocket='+'a'.repeat(43));
  let delivered=0;
  await client.follow('session',()=>{delivered++;},()=>{});
  const old=socketCallbacks.get('message');
  client.pause();old(null,JSON.stringify({type:'state',running:true}));
  assert.equal(delivered,0,'retired socket callbacks must not update the new interface');
});

test('UI mode preference persists and JavaScript cannot switch it from another origin', async () => {
  const {preferences,disk}=storage();
  const state=new Map();
  const AppStorage={get:key=>state.get(key),setOrCreate:(key,value)=>state.set(key,value)};
  const original=preferences.getPreferencesSync;
  preferences.getPreferencesSync=(...args)=>({...original(...args),flush:async()=>{}});
  const {PocketBridge}=load('PocketBridge',{
    '@kit.AbilityKit':{},'@kit.ArkWeb':{},'@kit.NotificationKit':{},'@kit.PushKit':{},
    '@kit.ArkData':{preferences},'@kit.ArkTS':{util:{generateRandomUUID:()=> 'device-id'}},
    './WindowAppearance':{WindowAppearance:{}},'./NativeExperience':{NativeExperience:{state:()=> '{}'}},
    './WidgetStore':{WidgetStore:{detailsEnabled:()=>false}}
  },{AppStorage});
  const controller={getLastJavascriptProxyCallingFrameUrl:()=> 'https://other.example.com/',getUrl:()=> 'https://dsh.example.com/',runJavaScript:async()=>{}};
  const bridge=new PocketBridge(context,controller,'https://dsh.example.com',async()=>{});
  await bridge.performNative('uiMode','native');
  assert.equal(state.get('uiMode'),'native');assert.equal(disk.get('dsh-pocket').get('uiMode'),'native');
  await assert.rejects(()=>bridge.performNative('uiMode','unknown'));
  bridge.request('request','uiMode','compatibility');
  await Promise.resolve();assert.equal(state.get('uiMode'),'native');
  await bridge.performNative('themeMode','dark');assert.equal(state.get('nativeThemeMode'),'dark');
});

test('native history grows past former limits and retains older pages on reconnect', () => {
  const { NativeSessionModel } = load('NativeSessionModel', {});
  const model = new NativeSessionModel();
  const rows = Array.from({length:2000}, (_,seq)=>({seq,id:'event-'+seq,text:'row '+seq}));
  model.apply({type:'snapshot',cursor:1999,beforeSeq:1000,messages:rows.slice(1000),hasMore:true});
  model.prepend({messages:rows.slice(0,1000),beforeSeq:0,hasMore:false});
  model.apply({type:'event',seq:2000,message:{id:'event-2000',seq:2000,text:'new'}});
  assert.equal(model.messages.length,2001);
  model.apply({type:'snapshot',cursor:2000,beforeSeq:1900,messages:model.messages.slice(1900),hasMore:true,replacements:[]});
  assert.equal(model.messages.length,2001);
  assert.equal(model.hasMore,false);
  assert.equal(model.historyBefore,0);
  model.apply({type:'start',attemptId:'a'});
  model.apply({type:'delta',attemptId:'a',index:0,text:'😀'.repeat(100000),reasoning:'思考'.repeat(100000)});
  assert.equal(model.streamText.length,200000);
  assert.equal(model.streamReasoning.length,200000);
});

test('virtual native text windows reconstruct complete Unicode without splitting surrogate pairs', () => {
  const { NativeTextSource } = load('NativeTextSource', {});
  const source = new NativeTextSource();
  const text = 'x'.repeat(4095) + '😀' + '正文😀'.repeat(100000);
  source.set(text);
  const parts = Array.from({length:source.totalCount()}, (_,index)=>source.getData(index));
  assert.equal(parts.join(''),text);
  assert.ok(parts.every(part=>!/^\p{Surrogate}/u.test(part)&&!/\p{Surrogate}$/u.test(part)));
});
test('older pages cannot resurrect history removed by a newer replacement', () => {
  const { NativeSessionModel } = load('NativeSessionModel', {});
  const model = new NativeSessionModel();
  model.apply({type:'snapshot',cursor:100,beforeSeq:90,messages:[{seq:100,id:'event-100',text:'replacement'}],hasMore:true,replacements:[{start:1,end:50}]});
  model.prepend({messages:[{seq:1,id:'event-1',text:'removed'},{seq:51,id:'event-51',text:'kept'}],beforeSeq:1,hasMore:false});
  assert.deepEqual(Array.from(model.messages,row=>row.seq),[51,100]);
});
