// Exercises service logic under kit mocks. This is not an ArkTS/Hvigor build.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import ts from 'typescript';
import { normalizedHistory, normalizeFollow } from '../src/native-protocol.mjs';

const services = new URL('../../harmony/entry/src/main/ets/services/', import.meta.url);
function load(name, kits, globals = {}) {
  const source = readFileSync(new URL(name + '.ets', services), 'utf8');
  const output = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS } });
  const module = { exports: {} };
  vm.runInNewContext(output.outputText, { module, exports: module.exports, setTimeout, clearTimeout, require: id => {
    if (!(id in kits) && id.startsWith('./') && existsSync(new URL(id.slice(2) + '.ets', services))) return load(id.slice(2), kits, globals);
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

test('widget task-name defaults, opt-out, cross-process restoration, expiry and logout serialization', async () => {
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
  assert.equal(WidgetStore.data(context).showCounts, true);
  assert.notEqual(disk.get('pocket-widget-snapshot').get('snapshot'), '');
  assert.equal(deliveries.length, 1, 'duplicate form instance IDs must not duplicate delivery');
  await WidgetStore.setDetails(context, false);
  await WidgetStore.update(context, snapshot);
  assert.equal(WidgetStore.data(context).showCounts, false);
  assert.equal(disk.get('pocket-widget-snapshot').get('snapshot'), '');
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

test('native transcript hides protocol bookkeeping across snapshots, live events and history', () => {
  const { NativeSessionModel } = load('NativeSessionModel', {});
  const model = new NativeSessionModel();
  model.apply({type:'snapshot',cursor:2,beforeSeq:0,messages:[
    {id:'event-1',seq:1,role:'assistant',text:'answer'},
    {id:'event-2',seq:2,role:'detail',label:'step/end',text:'{"turn":1}'}
  ]});
  model.apply({type:'event',seq:3,message:{id:'event-3',seq:3,role:'detail',label:'workspace/changes'}});
  model.apply({type:'event',seq:4,message:{id:'event-4',seq:4,role:'notice',label:'执行失败',text:'task failed'}});
  model.prepend({messages:[{id:'event-0',seq:0,role:'detail',label:'session/start'}],hasMore:false,beforeSeq:0});
  assert.equal(model.messages.map(x => x.id).join(','),'event-1,event-4');
});

test('empty session filtering uses the explicit DSH flag and preserves untitled content and active work', () => {
  const { nativeSessionVisible, NativeSessionModel } = load('NativeSessionModel', {});
  assert.equal(nativeSessionVisible({title:'named empty',blank:true},undefined),false);
  assert.equal(nativeSessionVisible({title:'新会话',blank:false},undefined),true);
  assert.equal(nativeSessionVisible({title:'',blank:false},undefined),true);
  assert.equal(nativeSessionVisible({title:'新会话',blank:true,running:true},undefined),true);
  assert.equal(nativeSessionVisible({title:'新会话'},undefined),false);
  const cached = new NativeSessionModel(); cached.messages = [{role:'user',text:'hello'}];
  assert.equal(nativeSessionVisible({title:'新会话',blank:true},cached),true);
});

test('Workspace lists honor archive, pin, manual order and search without mutating source rows',()=>{
  const {nativeWorkspaceSessions,nativeToolsParent}=load('NativeSessionModel',{});
  const rows=[
    {id:'a',title:'Alpha',blank:false,updatedAt:5,cwd:'/workspace/project'},
    {id:'b',title:'Beta',blank:false,updatedAt:6},
    {id:'empty',title:'New',blank:true,updatedAt:9},
    {id:'archived',title:'Archived',blank:false,updatedAt:10}
  ];
  const snapshot={items:[{workspaceId:'project',sessionIds:['b','a','empty']}],archivedSessionIds:['archived'],pinnedSessionIds:['a']};
  assert.equal(nativeWorkspaceSessions(rows,snapshot,'project','',new Map()).map(x=>x.id).join(','),'a,b');
  assert.equal(nativeWorkspaceSessions(rows,snapshot,'project','alpha',new Map()).map(x=>x.id).join(','),'a');
  assert.equal(rows.map(x=>x.id).join(','),'a,b,empty,archived');
  assert.equal(nativeToolsParent('queueEdit'),'queue');assert.equal(nativeToolsParent('efforts'),'modelsRoot');
  assert.equal(nativeToolsParent('models'),'modelsRoot');assert.equal(nativeToolsParent('modelsRoot'),'');
  assert.equal(nativeToolsParent('rename'),'');
});

test('native inline markdown preserves literal code and malformed text while styling nested runs', () => {
  const { nativeInlineMarkdown } = load('NativeInlineMarkdown', {});
  const runs = nativeInlineMarkdown('**bold and `a_*b`** · [readme](</workspace/docs/readme.md>) · [web](https://example.com/a_(b))');
  assert.equal(runs.map(x => x.text).join(''),'bold and a_*b · readme · web');
  assert.equal(runs.find(x => x.code).text,'a_*b');
  assert.equal(runs.find(x => x.code).bold,true);
  assert.equal(runs.find(x => x.text === 'readme').href,'/workspace/docs/readme.md');
  assert.equal(runs.find(x => x.text === 'web').href,'https://example.com/a_(b)');
  assert.equal(nativeInlineMarkdown('**unfinished').map(x => x.text).join(''),'**unfinished');
  assert.equal(nativeInlineMarkdown('`**literal**`').map(x => x.text).join(''),'**literal**');
});

test('foreground navigation wins over width changes and the session menu keeps the official action order', () => {
  const {nativeCanGoBack,nativeSessionMenu,nativeForkTitle}=load('NativeNavigation',{});
  assert.equal(nativeCanGoBack({wide:true,sessions:true,picker:true}),true);
  assert.equal(nativeCanGoBack({wide:true,sessions:true,tools:true}),true);
  assert.equal(nativeCanGoBack({wide:false,sessions:true,menu:true}),true);
  assert.equal(nativeCanGoBack({wide:false,sessions:false}),true);
  assert.equal(nativeCanGoBack({wide:true,sessions:false}),false);
  assert.equal(nativeSessionMenu(false).map(x=>x.id).join(','),'pin,rename,fork,archive,copyId');
  assert.equal(nativeSessionMenu(true,true).map(x=>x.id).join(','),'rename,fork,unarchive,copyId');
  assert.equal(nativeForkTitle('task (99999999999999999999)'),'task (100000000000000000000)');
  assert.equal(nativeForkTitle('任务（009）'),'任务（10）');
  assert.equal(nativeForkTitle('task'),'task (1)');
});

test('Host profile mirror serializes writes with the latest revision and restores authority after conflicts', async () => {
  const {NativeHostSettings}=load('NativeHostSettings',{});
  let revision=4, values={transcriptView:'standard'}, fail=false;
  const writes=[];
  const mirror=new NativeHostSettings(async raw=>{
    const request=JSON.parse(raw);
    if(request.operation==='settingsDescribe') return JSON.stringify({writable:true,namespaces:[{ns:'ui-chat',value:values,revision}]});
    writes.push(request);
    if(fail) { values={transcriptView:'compact'};revision++;throw Error('conflict'); }
    assert.equal(request.revision,revision,'queued write must take its revision when it executes');
    values={...values,[request.field]:request.value};return JSON.stringify({ns:'ui-chat',value:values,revision:++revision});
  });
  await mirror.refresh();
  await Promise.all([mirror.set('ui-chat','transcriptView','detailed'),mirror.set('ui-chat','foldedReplies','final')]);
  assert.equal(writes.map(x=>x.revision).join(','),'4,5');
  assert.equal(mirror.chat().mode,'detailed');assert.equal(mirror.chat().foldedReplies,'final');
  fail=true;await assert.rejects(()=>mirror.set('ui-chat','transcriptView','verbose'));
  assert.equal(mirror.chat().mode,'compact');
  assert.equal(mirror.description.namespaces[0].revision,7);
});

test('presentation policies share grouping while handling four modes, deferred collapse and final-only replies', () => {
  const types=load('NativeSessionModel',{}), preferences=load('NativeHostSettings',{});
  const {nativeTranscript,nativePresentTranscript,nativeReasoningPreview}=load('NativeTranscript',{'./NativeSessionModel':types});
  const message=(id,role,seq,rest={})=>Object.assign(new types.NativeMessage(),{id,role,seq,turn:1,step:1,...rest});
  const records=[message('human','user',1,{sourceKind:'user',text:'hello'}),
    message('tool','tool',2,{phase:'start',callId:'call',toolName:'read',text:'{"file_path":"src/app.ts"}'}),
    message('intermediate','assistant',3,{text:'progress'}),message('think','assistant',4,{reasoning:'Thought\n\nmore'}),
    message('answer','assistant',5,{text:'answer'}),message('end','turn',6,{eventType:'turn/end',outcome:'completed'})];
  for(const mode of ['compact','standard','detailed','verbose']) {
    const prefs=Object.assign(new preferences.NativeChatPreferences(),{mode});
    const visible=nativePresentTranscript(nativeTranscript(records,false),prefs,new Map());
    assert.equal(visible.filter(x=>x.role==='process').length,mode==='verbose'?2:0);
    const open=nativePresentTranscript(nativeTranscript(records,false),prefs,new Map([['turn:1',true]]));
    assert.equal(open.filter(x=>x.role==='process').length,2);
    assert.equal(open.find(x=>x.role==='process').flat,mode==='verbose');
    assert.equal(open.find(x=>x.role==='process').preview,mode!=='compact');
  }
  const prefs=Object.assign(new preferences.NativeChatPreferences(),{collapseTiming:'next-input',foldedReplies:'final'});
  assert.equal(nativePresentTranscript(nativeTranscript(records,false),prefs,new Map()).filter(x=>x.role==='process').length,2);
  const collapsed=nativePresentTranscript(nativeTranscript(records,false),prefs,new Map(),6);
  assert.equal(collapsed.some(x=>x.id==='intermediate'),false);assert.equal(collapsed.some(x=>x.id==='answer'),true);
  const live=nativePresentTranscript(nativeTranscript(records.slice(0,-1),true),prefs,new Map());
  assert.equal(live.find(x=>x.role==='process').flat,true);
  assert.equal(nativeReasoningPreview('unfinished line',true),'');
  assert.equal(nativeReasoningPreview('**First**\nmore\n\nSecond\nnot complete',true),'Second');
  assert.equal(nativeReasoningPreview('**First**\nbody',false),'First');
  const noAnswer=nativeTranscript(records.filter(x=>x.role!=='assistant'),false);
  assert.equal(noAnswer.find(x=>x.role==='process').foldable,true,'a completed turn without final answer remains foldable');
});

test('the journal retains hidden context and raw tool metadata without resurfacing it in Chat', () => {
  const {NativeSessionModel}=load('NativeSessionModel',{}), model=new NativeSessionModel();
  const frames=[
    {type:'event',event:{seq:1,type:'user/message',data:{source:{kind:'runtime'},content:[{type:'text',text:'injected context'}]}}},
    {type:'event',event:{seq:2,type:'tool/result',data:{meta:{path:'/workspace/a.ts',offset:1,lines:[]},message:{source:{callId:'read'},content:[{type:'text',text:'result'}]}}}}
  ];
  model.apply({type:'snapshot',cursor:2,...normalizedHistory(frames)});
  assert.equal(model.messages.some(x=>x.text==='injected context'),false);
  assert.equal(JSON.parse(model.journal.get(1)).data.source.kind,'runtime');
  assert.equal(JSON.parse(model.messages[0].metaRaw).path,'/workspace/a.ts');
  assert.equal(JSON.parse(model.messages[0].contentRaw)[0].text,'result');
});

test('native Chat merges call/results and nested PTC calls, splitting process groups only at replies or inputs', () => {
  const types = load('NativeSessionModel', {});
  const { nativeTranscript } = load('NativeTranscript', {'./NativeSessionModel':types});
  const event = (seq,type,data) => ({type:'event',event:{seq,time:1000+seq*100,type,data:{turn:1,step:1,...data}}});
  const history = normalizedHistory([
    event(0,'turn/start',{}),
    event(1,'user/message',{source:{kind:'user'},content:[{type:'text',text:'hello'}]}),
    event(2,'assistant/message',{message:{content:[{type:'reasoning',text:'think'},{type:'tool-call',id:'root',name:'run_code',arguments:'{}'}]}}),
    event(3,'tool/call',{callId:'root',name:'run_code',arguments:'{"code":"read()"}'}),
    event(4,'tool/ptc-dispatch-start',{rootCallId:'root',parentCallId:'root',subCallId:'child',name:'read',arguments:{file_path:'src/app.ts'}}),
    event(5,'tool/ptc-dispatch',{rootCallId:'root',parentCallId:'root',subCallId:'child',name:'read',content:[{type:'text',text:'source'}]}),
    event(6,'tool/result',{message:{source:{callId:'root'},content:[{type:'text',text:'done'}]}}),
    event(7,'assistant/message',{message:{content:[{type:'text',text:'progress'}]}}),
    event(8,'tool/call',{step:2,callId:'shell',name:'exec_command',arguments:'{"cmd":"echo ok"}'}),
    event(9,'tool/result',{step:2,message:{source:{callId:'shell'},content:[{type:'text',text:'ok'}]}}),
    event(10,'assistant/message',{step:2,message:{content:[{type:'text',text:'answer'}]}}),
    event(11,'turn/end',{reason:{kind:'completed'}})
  ]);
  const rows = nativeTranscript(history.messages,false);
  const groups = rows.filter(x=>x.role==='process');
  assert.equal(groups.length,2,JSON.stringify(rows.map(x=>({id:x.id,role:x.role,turn:x.turnKey,children:x.children.map(y=>y.id)}))));
  const root=groups[0].children.find(x=>x.role==='tool');
  assert.equal(root.toolName,'run_code'); assert.equal(root.status,'success');
  assert.equal(root.args,'{"code":"read()"}'); assert.equal(root.output,'done');
  assert.equal(root.children.length,1); assert.equal(root.children[0].toolName,'read');
  assert.equal(root.children[0].output,'source');
  assert.equal(groups[0].children.filter(x=>x.role==='reasoning').length,1);
  assert.equal(rows.filter(x=>x.role==='turn-control').length,1);
  assert.ok(groups.every(x=>x.foldable));
  assert.equal(rows.filter(x=>x.role==='assistant').map(x=>x.text).join(','),'progress,answer');
  assert.equal(rows.filter(x=>x.role==='turn-footer').length,1);
  const mixed=nativeTranscript(normalizedHistory([
    event(12,'assistant/message',{message:{content:[{type:'text',text:'first'},{type:'reasoning',text:'thought'},{type:'text',text:'second'}]}})
  ]).messages,false);
  assert.equal(mixed.map(x=>x.role).join(','),'assistant,process,assistant','finalized assistant blocks retain their source order');
});

test('running activity uses latest still-running start time and exact upstream tool-name categories', () => {
  const types=load('NativeSessionModel',{});
  const {nativeTranscript,nativeToolCategory,nativeToolDetail}=load('NativeTranscript',{'./NativeSessionModel':types});
  const rows=[
    {id:'a',seq:1,turn:1,step:1,role:'tool',callId:'a',toolName:'exec_command',phase:'start',time:10,text:'{"cmd":"test","description":"Run checks"}'},
    {id:'b',seq:2,turn:1,step:1,role:'tool',callId:'b',toolName:'read',phase:'start',time:20,text:'{"file_path":"src/app.ts"}'},
    {id:'c',seq:3,turn:1,step:1,role:'tool',callId:'b',phase:'result',time:30,text:'contents'}
  ];
  const group=nativeTranscript(rows,true)[0];
  assert.equal(group.label,'正在运行命令 · Run checks');
  assert.equal(nativeToolCategory('functions.read'),'tools');
  assert.equal(nativeToolCategory('terminal_inspect'),'search');
  assert.equal(nativeToolCategory('subagent_codex'),'subagents');
  assert.equal(nativeToolDetail({args:'{"questions":[{"question":"Choose scope"}]}',phase:'start',toolName:'request_user_input'}),'Choose scope');
  const ended=nativeTranscript(rows.concat([{id:'end',seq:4,turn:1,step:1,role:'boundary'}]),true)[0];
  assert.equal(ended.children.find(x=>x.callId==='a').status,'interrupted');
});

test('interleaved human input keeps per-group disclosure rather than whole-turn folding', () => {
  const types=load('NativeSessionModel',{});
  const {nativeTranscript}=load('NativeTranscript',{'./NativeSessionModel':types});
  const rows=nativeTranscript([
    {id:'call',seq:1,turn:1,role:'tool',callId:'a',toolName:'read',phase:'start',text:'{}'},
    {id:'steer',seq:2,turn:1,role:'user',sourceKind:'user',text:'different scope'},
    {id:'answer',seq:3,turn:1,role:'assistant',text:'done'},
    {id:'end',seq:4,turn:1,role:'turn',eventType:'turn/end',outcome:'completed'}
  ],false);
  assert.equal(rows.some(x=>x.role==='turn-control'),false);
  assert.equal(rows.find(x=>x.role==='process').foldable,false);
});

test('streamed tool argument fragments settle once and never become assistant placeholder text', () => {
  const {NativeSessionModel}=load('NativeSessionModel',{});
  const model=new NativeSessionModel();
  model.apply({type:'snapshot',cursor:0,messages:[],attemptId:'a',nextIndex:0});
  for (const [index,chunk] of [
    {type:'tool-call-delta',id:'call',name:'exec_command',argumentsDelta:'{"cmd":'},
    {type:'tool-call-delta',id:'call',argumentsDelta:'"echo ok"}'},
    {type:'block-end',block:{type:'tool-call',id:'call',name:'exec_command',arguments:'{"cmd":"echo ok"}'}}
  ].entries()) model.apply(normalizeFollow({type:'assistant-stream',frame:{type:'chunk',attemptId:'a',index,chunk}}));
  assert.equal(model.streamTools.length,1);
  assert.equal(model.streamTools[0].text,'{"cmd":"echo ok"}');
  assert.equal(model.streamText,'');
  model.apply({type:'end',attemptId:'a'}); assert.equal(model.streamTools.length,0);
});

test('native transport shares only gateway cookies, disables redirects and never retries prompts', async () => {
  const calls = [], configured = [];
  let code = 200, made = 0, streamBody = '{}';
  let cookie = Promise.resolve('other=hidden; pocket=' + 'a'.repeat(43));
  const socketCallbacks = new Map();
  const socket = { on: (event, callback) => socketCallbacks.set(event, callback), off: event => socketCallbacks.delete(event),
    connect: async (_url, options) => {
      assert.equal(options.supportOriginPort,true,'the Harmony stack must retain the gateway port in Origin');
      socketCallbacks.get('open')(null);
      return true;
    }, close: async () => true };
  const network = { http: { RequestMethod: { GET:'GET',POST:'POST' }, HttpDataType:{STRING:'string'}, createHttp:()=>({
    on(event, callback) { this[event] = callback; },
    async requestInStream(url, options) { calls.push({url,options}); const encoded = new TextEncoder().encode(streamBody); this.dataReceive(encoded.buffer); this.dataEnd(); return code; },
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
  streamBody = JSON.stringify({text:'完整😀'.repeat(400000)});
  assert.equal(await client.operation('{}'),streamBody,'native HTTP must not clip responses above the old 2MB ceiling');
  streamBody = '{}';
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
    './WidgetStore':{WidgetStore:{detailsEnabled:()=>false}},
    'entry/PushKitAdapter':{PushKitAdapter:{supported:false}},
    './BackgroundMonitor':{BackgroundMonitor:{}}
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
