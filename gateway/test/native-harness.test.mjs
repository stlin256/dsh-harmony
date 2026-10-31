import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer, request } from 'node:http';
import { randomBytes, createHash } from 'node:crypto';
import { once } from 'node:events';
import WebSocket, { WebSocketServer } from 'ws';
import { openStore } from '../src/store.mjs';
import { createApp } from '../src/app.mjs';
import { normalizeFollow, normalizedHistory, richBlocks, normalizeRecord } from '../src/native-protocol.mjs';
import { nativeHeartbeatPolicy } from '../src/native-harness.mjs';

const origin = 'https://dsh.example.com';

test('native heartbeat policy keeps foreground and background deadlines bounded', () => {
  assert.deepEqual(nativeHeartbeatPolicy(), { intervalMs: 5000, deadlineMs: 20000, openingMs: 30000 });
  assert.deepEqual(nativeHeartbeatPolicy('foreground'), { intervalMs: 5000, deadlineMs: 20000, openingMs: 30000 });
  assert.deepEqual(nativeHeartbeatPolicy('background'), { intervalMs: 15000, deadlineMs: 45000, openingMs: 45000 });
});

async function setup(t, options = {}) {
  const calls = [];
  const uploads = [];
  const backend = createServer(async (req, res) => {
    if (req.method === 'GET' || req.method === 'HEAD') {
      assert.equal(req.headers.cookie, 'harness=server-only');
      const route = new URL(req.url, 'http://localhost');
      if (options.unavailableExports) { res.writeHead(404).end(); return; }
      if (options.htmlExport) { res.setHeader('Content-Type','text/html'); res.end('<h1>Authentication required</h1>'); return; }
      assert.equal(route.searchParams.get('sessionId'), 'session');
      if (route.pathname === '/api/session.markdown') { res.setHeader('Content-Type','text/markdown'); res.end('# Complete transcript\n\nnot just the visible window'); return; }
      if (route.pathname === '/api/session.export') { assert.equal(route.searchParams.get('includeDescendants'),'true'); res.setHeader('Content-Type','application/zip'); res.end(Buffer.from([0x50,0x4b,3,4,0,255])); return; }
      res.writeHead(404).end(); return;
    }
    const route = new URL(req.url, 'http://localhost');
    const chunks = []; for await (const part of req) chunks.push(part);
    if (route.pathname === '/api/session/uploadFileBinary') {
      assert.equal(req.headers.cookie, 'harness=server-only');
      assert.equal(req.headers['content-type'], 'application/octet-stream');
      const bytes = Buffer.concat(chunks);
      uploads.push({ query: Object.fromEntries(route.searchParams), bytes, headers: req.headers });
      res.setHeader('Content-Type', 'application/json');
      res.end(JSON.stringify({ ok: true, value: { receiptId: 'receipt-1',
        file: { attachmentId: 'attachment-1', name: route.searchParams.get('name'), bytes: bytes.length } } }));
      return;
    }
    const value = JSON.parse(Buffer.concat(chunks).toString());
    calls.push({ headers: req.headers, value });
    if (options.workspaceFileError && value.method === 'workspaceFiles/stat') {
      res.setHeader('Content-Type', 'application/json');
      res.end(JSON.stringify({ type: 'server-response', rpcId: value.rpcId,
        result: { ok: false, error: { code: 'workspace-file/not-found' } } }));
      return;
    }
    let result;
    if (value.method === 'workspaceFiles/read') {
      result = { absolutePath: '/workspace/project/README.md', version: 'v7', text: '# Fixture\n\npreview', lines: 3, offset: 1, eof: true };
    } else if (value.method === 'workspaceFiles/stat') {
      result = { absolutePath: '/workspace/project/file.txt', version: 'v8', bytes: 7 };
    } else if (value.method === 'workspaceFiles/list') {
      const path = value.payload.args.path;
      result = { path: path === '.' ? '' : path, entries: [
        { name: 'nested', type: 'directory' },
        { name: 'file.txt', type: 'file', size: 7 },
        { name: 'socket', type: 'other' }
      ], truncated: false };
    } else if (value.method === 'workspaceFiles/readBytes') {
      const bytes = options.emptyReadBytes ? [] : [0, 1, 2, 255, 65, 66, 67];
      const form = new FormData();
      form.set('metadata', JSON.stringify({
        type: 'server-response',
        rpcId: value.rpcId,
        result: { ok: true, value: {
          absolutePath: '/workspace/project/file.txt', version: 'v8', bytes: bytes.length,
          offset: value.payload.args.options.range.offset, data: null, eof: true
        } },
        attachments: [{ codec: 'bytes', part: 'bytes-0', path: ['data'] }]
      }));
      form.set('bytes-0', new Blob([Buffer.from(bytes)]), 'bytes.bin');
      if (options.unexpectedAttachment) {
        form.set('bytes-extra', new Blob([Buffer.from([9])]), 'extra.bin');
      }
      const encoded = new Response(form);
      res.writeHead(200, Object.fromEntries(encoded.headers));
      res.end(Buffer.from(await encoded.arrayBuffer()));
      return;
    } else if (value.method === 'session/list') {
      assert.deepEqual(value.payload.args, { _request: {} }, 'source _request parameter must keep its exact wire name');
      result = { items: [{ sessionId:'session', blank:false, running:true, updatedAt:42, projections:{values:{title:'Native session'}} }] };
    } else if (value.method === 'session/create') result = {sessionId:value.payload.args.request.sessionId};
    else if (value.method === 'settings/describe') result = {writable:true,namespaces:[
      {ns:'ui-chat',value:{transcriptView:'standard'},revision:4}, {ns:'private-provider',value:{credential:'must-not-forward'},revision:1}
    ]};
    else if (value.method === 'settings/mutate') result = {ns:value.payload.args.ns,value:{[value.payload.args.ops[0].path[0]]:value.payload.args.ops[0].value},revision:5};
    else if (value.method === 'session/page') result = { records:[{type:'event',event:{seq:0,type:'user/message',data:{content:[{type:'text',text:'older'}]}}}], cursor:3,hasMore:false };
    else result = {accepted:true};
    res.setHeader('Content-Type','application/json');
    res.end(JSON.stringify({type:'server-response',rpcId:value.rpcId,result:{ok:true,value:result}}));
  });
  const upstreamWS = new WebSocketServer({noServer:true});
  const openings = [];
  backend.on('upgrade',(req,socket,head)=>{
    assert.equal(req.url,'/api/remote.mux');
    assert.equal(req.headers.cookie,'harness=server-only');
    assert.equal(req.headers.origin,`http://127.0.0.1:${backend.address().port}`);
    upstreamWS.handleUpgrade(req,socket,head,ws=>{
      upstreamWS.emit('connection',ws);
      ws.on('message',raw=>{
        const frame=JSON.parse(raw); openings.push(frame);
        assert.equal(frame.type,'open');
        if (frame.endpoint === 'workspace/follow') {
          assert.deepEqual(frame.payload,{args:{}});
          ws.send(JSON.stringify({type:'item',streamId:frame.streamId,value:{type:'baseline',value:{items:[
            {workspaceId:'workspace',title:'Project',path:'/workspace/project',sessionIds:['session']}
          ],archivedSessionIds:['archived'],pinnedSessionIds:['session']}}})); return;
        }
        if (frame.endpoint === 'userQuestions/attachWait') {
          assert.deepEqual(frame.payload.args,{agent:'session',callId:'timed-call'});
          ws.send(JSON.stringify({type:'item',streamId:frame.streamId,value:{remainingMs:80}})); return;
        }
        if (frame.endpoint === '$events') {
          assert.deepEqual(frame.payload, {args:{}});
          ws.send(JSON.stringify({type:'item',streamId:frame.streamId,value:{type:'ready',clientId:'client-generation',host:{home:'~'}}}));
          return;
        }
        if (options.modern && ['session/observeState', 'session/observeProjections'].includes(frame.endpoint)) {
          ws.send(JSON.stringify({ type: 'error', streamId: frame.streamId, error: { code: 'gateway/invocation-unavailable' } })); return;
        }
        if (frame.endpoint === 'session/control') {
          assert.deepEqual(frame.payload, { args: {} });
          ws.send(JSON.stringify({ type: 'item', streamId: frame.streamId, value: { type: 'baseline', value: {
            projections: { session: { asOfSeq: 0, values: { userQuestions: { active: [] } } } }
          } } })); return;
        }
        assert.equal(frame.payload.args.request.sessionId || frame.payload.args.request.address.sessionId,'session');
        if(frame.endpoint==='session/follow') {
          ws.send(JSON.stringify({type:'item',streamId:frame.streamId,value:{type:'snapshot',cursor:0,hasMore:false,
            records:[{type:'event',event:{seq:0,type:'user/message',data:{content:[{type:'text',text:options.text || 'hello'}]}}}],
            assistantStream:{activeAttempt:{attemptId:'attempt',nextIndex:2,stream:[{type:'text-chunks',texts:['he','l']}]}}}}));
          ws.send(JSON.stringify({type:'item',streamId:frame.streamId,value:{type:'assistant-stream',frame:{type:'chunk',attemptId:'attempt',index:2,chunk:{type:'text-delta',text:'lo'}}}}));
        } else if(frame.endpoint==='session/observeState') ws.send(JSON.stringify({type:'item',streamId:frame.streamId,value:{running:true,pendingInput:['approval']}}));
      });
    });
  });
  await new Promise(resolve=>backend.listen(0,'127.0.0.1',resolve));
  const db=openStore(':memory:');
  const token=randomBytes(32).toString('base64url');
  const cookie='pocket='+token;
  db.prepare('INSERT INTO sessions VALUES (?,?)').run(createHash('sha256').update(token).digest('hex'),Date.now()+60000);
  const pocket=createApp({db,origin,upstream:`http://127.0.0.1:${backend.address().port}`,upstreamCookie:'harness=server-only',bootstrapSecret:'bootstrap-'.repeat(8),eventSecret:'events-'.repeat(8),pushConfigured:true});
  const server=createServer(pocket.app); server.on('upgrade',pocket.upgrade);
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  t.after(()=>{pocket.close();for(const ws of upstreamWS.clients)ws.terminate();upstreamWS.close();server.closeAllConnections();server.close();backend.closeAllConnections();backend.close();db.close();});
  const call=(path,body,authorized=true)=>new Promise((resolve,reject)=>{
    const req=request({hostname:'127.0.0.1',port:server.address().port,path,method:body===undefined?'GET':'POST',headers:{host:'dsh.example.com',origin,'content-type':'application/json',...(authorized?{cookie:typeof authorized === 'string' ? authorized : cookie}:{})}},res=>{
      const chunks=[];res.on('data',part=>chunks.push(part));res.on('end',()=>{
        const buffer=Buffer.concat(chunks);
        resolve({status:res.statusCode,headers:res.headers,buffer,text:buffer.toString()});
      });
    });req.on('error',reject);req.end(body===undefined?undefined:JSON.stringify(body));
  });
  const upload=(path,bytes,headers={})=>new Promise((resolve,reject)=>{
    const req=request({hostname:'127.0.0.1',port:server.address().port,path,method:'POST',
      headers:{host:'dsh.example.com',origin,'content-type':'application/octet-stream',cookie,...headers}},res=>{
      const chunks=[];res.on('data',part=>chunks.push(part));res.on('end',()=>{
        const buffer=Buffer.concat(chunks);resolve({status:res.statusCode,text:buffer.toString()});
      });
    });req.on('error',reject);req.end(bytes);
  });
  const connect=(headers={})=>new WebSocket(`ws://127.0.0.1:${server.address().port}/pocket/native/live?sessionId=session`,{headers:{Host:'dsh.example.com',Origin:origin,Cookie:cookie,...headers}});
  return {call,upload,calls,uploads,connect,openings,db,emit: value => { for (const ws of upstreamWS.clients) ws.send(JSON.stringify({type:'item',streamId:'interactions',value})); }};
}

test('modern Harness control stream replaces removed per-session observers without dropping history', async t => {
  const { connect, openings } = await setup(t, { modern: true });
  const ws = connect();
  const frames = [];
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(Error('control fallback timeout')), 2000);
    ws.on('message', raw => {
      frames.push(JSON.parse(raw));
      if (frames.some(x => x.type === 'questions') && frames.some(x => x.type === 'state') && frames.some(x => x.type === 'snapshot')) {
        clearTimeout(timer); resolve();
      }
    });
    ws.once('error', reject);
  });
  assert.equal(openings.filter(x => x.endpoint === 'session/control').length, 1);
  assert.equal(frames.some(x => x.type === 'error'), false);
  ws.close();
});

test('header utilities export complete Host content and profile writes use named revision arguments', async t => {
  const {call,calls}=await setup(t);
  const markdown=await call('/pocket/api/native/export?sessionId=session&format=markdown');
  assert.equal(markdown.status,200);assert.match(markdown.text,/not just the visible window/);
  assert.equal((await call('/pocket/api/native/export?sessionId=session&format=zip')).status,200);
  assert.equal((await call('/pocket/api/native/export?sessionId=../bad&format=zip')).status,400);
  assert.equal((await call('/pocket/api/native/export?sessionId=session&format=markdown',undefined,false)).status,401);
  assert.deepEqual(JSON.parse((await call('/pocket/api/native/operation',{operation:'capabilities',sessionId:'session'})).text),{copyMarkdown:true,downloadLog:true});
  const settings=JSON.parse((await call('/pocket/api/native/operation',{operation:'settingsDescribe'})).text);
  assert.equal(settings.namespaces.length,1);assert.doesNotMatch(JSON.stringify(settings),/must-not-forward/);
  assert.deepEqual(calls.at(-1).value.payload.args,{});
  assert.equal((await call('/pocket/api/native/operation',{operation:'settingsSet',ns:'ui-chat',field:'transcriptView',value:'detailed',revision:4})).status,200);
  assert.equal(calls.at(-1).value.method,'settings/mutate');
  assert.deepEqual(calls.at(-1).value.payload.args,{ns:'ui-chat',ops:[{op:'set',path:['transcriptView'],value:'detailed'}],expectedRevision:4});
  for (const body of [
    {ns:'provider',field:'apiKey',value:'never'}, {ns:'ui-chat',field:'transcriptView',value:'invented'},
    {ns:'ui-theme',field:'fontSize',value:23}, {ns:'ui-chat',field:'collapseTiming',value:'completion',revision:-1}
  ]) assert.equal((await call('/pocket/api/native/operation',{operation:'settingsSet',revision:4,...body})).status,400);
});

test('native file preview uses the official workspaceFiles scope and bounded ranges', async t => {
  const { call, calls } = await setup(t);
  const response = await call('/pocket/api/native/file', { sessionId: 'session', path: 'README.md', offset: 1, limit: 80 });
  assert.equal(response.status, 200);
  assert.deepEqual(JSON.parse(response.text), {
    absolutePath: '/workspace/project/README.md', version: 'v7', text: '# Fixture\n\npreview',
    lines: 3, offset: 1, eof: true
  });
  assert.equal(calls.at(-1).value.method, 'workspaceFiles/read');
  assert.deepEqual(calls.at(-1).value.payload.args, {
    workspaceFileScopeId: 'session', path: 'README.md', range: { offset: 1, limit: 80 }
  });
  assert.equal((await call('/pocket/api/native/file', { sessionId: 'session', path: 'README.md', offset: 0 })).status, 400);
  assert.equal((await call('/pocket/api/native/file', { sessionId: 'session', path: 'README.md', limit: 501 })).status, 400);
});

test('native file browser resolves file types, directories and authenticated binary windows', async t => {
  const { call, calls } = await setup(t);
  const stat = await call('/pocket/api/native/file/stat', { sessionId: 'session', path: 'file.txt' });
  assert.equal(stat.status, 200);
  assert.deepEqual(JSON.parse(stat.text), {
    absolutePath: '/workspace/project/file.txt', version: 'v8', bytes: 7
  });
  assert.equal(calls.at(-1).value.method, 'workspaceFiles/stat');
  assert.deepEqual(calls.at(-1).value.payload.args, {
    workspaceFileScopeId: 'session', path: 'file.txt'
  });

  const list = await call('/pocket/api/native/file/list', { sessionId: 'session', path: 'src' });
  assert.equal(list.status, 200);
  assert.deepEqual(JSON.parse(list.text), {
    path: 'src', entries: [
      { name: 'nested', type: 'directory' },
      { name: 'file.txt', type: 'file', size: 7 },
      { name: 'socket', type: 'other' }
    ], truncated: false
  });
  assert.equal(calls.at(-1).value.method, 'workspaceFiles/list');

  const nested = await call('/pocket/api/native/file/list', { sessionId: 'session', path: 'src/nested' });
  assert.equal(nested.status, 200);
  assert.deepEqual(calls.at(-1).value.payload.args, {
    workspaceFileScopeId: 'session', path: 'src/nested'
  });

  const root = await call('/pocket/api/native/file/list', { sessionId: 'session', path: '' });
  assert.equal(root.status, 200);
  assert.equal(JSON.parse(root.text).path, '');
  assert.deepEqual(calls.at(-1).value.payload.args, {
    workspaceFileScopeId: 'session', path: '.'
  });

  const bytes = await call('/pocket/api/native/file/bytes', {
    sessionId: 'session', path: 'file.txt', offset: 0, length: 8
  });
  assert.equal(bytes.status, 200);
  assert.deepEqual([...bytes.buffer], [0, 1, 2, 255, 65, 66, 67]);
  assert.match(bytes.headers['content-type'], /^application\/octet-stream/);
  const metadata = JSON.parse(Buffer.from(bytes.headers['x-dsh-file-window'], 'base64url').toString());
  assert.deepEqual(metadata, {
    protocol: 1, absolutePath: '/workspace/project/file.txt', version: 'v8',
    bytes: 7, offset: 0, eof: true, length: 7
  });
  assert.equal(calls.at(-1).value.method, 'workspaceFiles/readBytes');
  assert.deepEqual(calls.at(-1).value.payload.args.options, { range: { offset: 0, length: 8 } });

  assert.equal((await call('/pocket/api/native/file/stat', { sessionId: '../bad', path: 'x' })).status, 400);
  assert.equal((await call('/pocket/api/native/file/list', { sessionId: 'session', path: 'x'.repeat(4097) })).status, 400);
  assert.equal((await call('/pocket/api/native/file/bytes', {
    sessionId: 'session', path: 'file.txt', length: 2 * 1024 * 1024 + 1
  })).status, 400);
});

test('native file routes preserve stable workspace-file failures', async t => {
  const { call } = await setup(t, { workspaceFileError: true });
  const stat = await call('/pocket/api/native/file/stat', { sessionId: 'session', path: 'missing.py' });
  assert.equal(stat.status, 409);
  assert.deepEqual(JSON.parse(stat.text), {
    error: '操作未确认，请刷新',
    code: 'workspace-file/not-found'
  });
});

test('native workspace file surface is read-only and rejects write-shaped routes', async t => {
  const { call, calls } = await setup(t);
  await call('/pocket/api/native/file/stat', { sessionId: 'session', path: 'file.txt' });
  await call('/pocket/api/native/file/list', { sessionId: 'session', path: '' });
  await call('/pocket/api/native/file/bytes', {
    sessionId: 'session', path: 'file.txt', offset: 0, length: 16
  });
  assert.deepEqual(calls.map(row => row.value.method), [
    'workspaceFiles/stat', 'workspaceFiles/list', 'workspaceFiles/readBytes'
  ]);
  for (const route of ['write', 'delete', 'rename', 'create', 'upload']) {
    assert.equal((await call('/pocket/api/native/file/' + route, {
      sessionId: 'session', path: 'file.txt'
    })).status, 404);
  }
});

test('native binary windows accept empty files and reject unexpected multipart parts', async t => {
  const empty = await setup(t, { emptyReadBytes: true });
  const value = await empty.call('/pocket/api/native/file/bytes', {
    sessionId: 'session', path: 'empty.txt', offset: 0, length: 16
  });
  assert.equal(value.status, 200);
  assert.equal(value.buffer.length, 0);
  const metadata = JSON.parse(Buffer.from(value.headers['x-dsh-file-window'], 'base64url').toString());
  assert.equal(metadata.bytes, 0);
  assert.equal(metadata.length, 0);

  const invalid = await setup(t, { unexpectedAttachment: true });
  const rejected = await invalid.call('/pocket/api/native/file/bytes', {
    sessionId: 'session', path: 'file.txt', offset: 0, length: 16
  });
  assert.equal(rejected.status, 502);
});

test('older Host exports are negotiated and an HTML login response never becomes a transcript or archive',async t=>{
  const old=await setup(t,{unavailableExports:true});
  assert.deepEqual(JSON.parse((await old.call('/pocket/api/native/operation',{operation:'capabilities',sessionId:'session'})).text),{copyMarkdown:false,downloadLog:false});
  const html=await setup(t,{htmlExport:true});
  assert.deepEqual(JSON.parse((await html.call('/pocket/api/native/operation',{operation:'capabilities',sessionId:'session'})).text),{copyMarkdown:false,downloadLog:false});
  assert.equal((await html.call('/pocket/api/native/export?sessionId=session&format=markdown')).status,502);
  assert.equal((await html.call('/pocket/api/native/export?sessionId=session&format=zip')).status,502);
});

test('native adapter uses official RPC envelopes and keeps upstream credentials server-side',async t=>{
  const {call,calls}=await setup(t);
  assert.equal((await call('/pocket/api/native/sessions',undefined,false)).status,401);
  const sessions=await call('/pocket/api/native/sessions');
  assert.equal(sessions.status,200);
  assert.deepEqual(JSON.parse(sessions.text),{protocol:2,truncated:false,items:[{id:'session',title:'Native session',titleKnown:true,blank:false,running:true,updatedAt:42}]});
  assert.equal((await call('/pocket/api/native/create',{requestId:'new-session'})).status,200);
  assert.equal((await call('/pocket/api/native/prompt',{sessionId:'session',requestId:'request',text:'test prompt'})).status,200);
  assert.equal(calls.at(-1).value.method,'session/prompt');
  assert.deepEqual(calls.at(-1).value.payload.args.request.content,[{type:'text',text:'test prompt'}]);
  assert.equal((await call('/pocket/api/native/cancel',{sessionId:'session'})).status,200);
  assert.equal((await call('/pocket/api/native/prompt',{sessionId:'../bad',requestId:'request',text:'x'})).status,400);
  assert.equal((await call('/pocket/api/native/prompt',{sessionId:'session',requestId:'request',text:'x'.repeat(100000)})).status,200);
  const page=await call('/pocket/api/native/page',{sessionId:'session',beforeSeq:3});
  assert.equal(JSON.parse(page.text).messages[0].text,'older');
  for(const call of calls) {
    assert.equal(call.headers.cookie,'harness=server-only');
    assert.doesNotMatch(JSON.stringify(call.value),/pocket=/);
  }
});

test('Workspace baseline, named Session creation and archive/pin commands use the public controller contracts',async t=>{
  const {call,calls}=await setup(t);
  const response=await call('/pocket/api/native/workspaces');
  const baseline=JSON.parse(response.text);
  assert.equal(baseline.available,true);assert.equal(baseline.items[0].workspaceId,'workspace');
  assert.deepEqual(baseline.archivedSessionIds,['archived']);
  assert.equal((await call('/pocket/api/native/create',{requestId:'reusable-blank',workspaceId:'workspace'})).status,200);
  assert.deepEqual(calls.at(-1).value.payload.args.request,{sessionId:'reusable-blank',workspaceId:'workspace'});
  assert.equal((await call('/pocket/api/native/create',{requestId:'new',workspaceId:'workspace',cwd:'/workspace/other'})).status,400);
  for(const [operation,method] of [['workspaceCreate','create'],['workspaceRename','rename'],['archive','archiveSession'],['unarchive','unarchiveSession'],['pin','pinSession'],['unpin','unpinSession']]) {
    const body={operation,sessionId:'session',workspaceId:'workspace',path:'/workspace/project',title:'Renamed'};
    assert.equal((await call('/pocket/api/native/operation',body)).status,200);
    assert.equal(calls.at(-1).value.method,'workspace/'+method);
    const expected=operation==='workspaceCreate'?{path:body.path}:operation==='workspaceRename'?{workspaceId:body.workspaceId,title:body.title}:{sessionId:body.sessionId};
    assert.deepEqual(calls.at(-1).value.payload.args,{request:expected});
  }
  assert.equal((await call('/pocket/api/native/operation',{operation:'workspaceRename',workspaceId:'../bad',title:'x'})).status,400);
});

test('session ordering maps only the public workspace membership RPC', async t => {
  const { call, calls } = await setup(t);
  const response = await call('/pocket/api/native/operation', {
    operation: 'sessionInsertBefore',
    workspaceId: 'workspace',
    sessionId: 'session',
    beforeSessionId: 'next-session'
  });
  assert.equal(response.status, 200);
  assert.equal(calls.at(-1).value.method, 'workspace/insertSessionBefore');
  assert.deepEqual(calls.at(-1).value.payload.args, {
    request: {
      workspaceId: 'workspace', sessionId: 'session', beforeSessionId: 'next-session'
    }
  });
  assert.equal((await call('/pocket/api/native/operation', {
    operation: 'sessionInsertBefore', workspaceId: '../bad', sessionId: 'session'
  })).status, 400);
  assert.equal((await call('/pocket/api/native/operation', {
    operation: 'sessionInsertBefore', workspaceId: 'workspace', sessionId: 'session',
    beforeSessionId: '../bad'
  })).status, 400);
});

test('native live channel restores stream baseline and revokes both sockets on logout',async t=>{
  const {connect,call,openings}=await setup(t);
  const ws=connect(); const frames=[];
  const ready=new Promise((resolve,reject)=>{
    const timeout=setTimeout(()=>reject(Error('stream timeout')),5000);
    ws.on('error',reject);
    ws.on('message',raw=>{const frame=JSON.parse(raw);frames.push(frame);if(frames.some(item=>item.type==='state')&&frames.some(item=>item.type==='delta')){clearTimeout(timeout);resolve();}});
  });
  await ready;
  assert.equal(frames.find(frame=>frame.type==='snapshot').text,'hel');
  assert.equal(frames.find(frame=>frame.type==='delta').text,'lo');
  assert.equal(frames.find(frame=>frame.type==='state').waiting,true);
  assert.deepEqual(openings.map(frame=>frame.endpoint),['$events','session/follow','session/observeState','session/observeProjections']);
  const closed=once(ws,'close');
  assert.equal((await call('/pocket/api/logout',{})).status,200);
  await closed;
  assert.equal(ws.readyState,WebSocket.CLOSED);
});

test('native stream rejects foreign origins and client command injection',async t=>{
  const {connect}=await setup(t);
  const rejected=connect({Origin:'https://other.example.com'});
  await once(rejected,'error');
  const ws=connect(); await once(ws,'open');
  const closed=once(ws,'close');
  ws.send(JSON.stringify({endpoint:'session/prompt',text:'injected'}));
  const [code]=await closed; assert.equal(code,1008);
});

test('normalization respects history replacements and produces native code blocks',()=>{
  const history=normalizedHistory([
    {type:'event',event:{seq:1,type:'user/message',data:{content:[{type:'text',text:'old'}]}}},
    {type:'event',event:{seq:2,type:'user/message',surfaceOp:{op:'replace',startSeq:1,endSeq:1},data:{content:[{type:'text',text:'new'}]}}}
  ]);
  assert.equal(history.messages.length,1);assert.equal(history.messages[0].text,'new');
  assert.equal(richBlocks('text\n```js\nconst x=1;\n```')[1].kind,'code');
  assert.deepEqual(normalizeFollow({type:'assistant-stream',frame:{type:'chunk',attemptId:'a',index:1,chunk:{type:'reasoning-delta',text:'thinking'}}}),
    {type:'delta',attemptId:'a',index:1,text:'',reasoning:'thinking'});
});

test('Chat filters injected source kinds at the durable source field while retaining actual human text', () => {
  const message=(source,text='context')=>({type:'event',event:{seq:1,type:'user/message',data:{source,content:[{type:'text',text}]}}});
  for(const kind of ['agent-instructions','runtime-context','session-reference','skill-invocation','compact-checkpoint']) {
    assert.equal(normalizeRecord(message({kind})),null,kind);
  }
  assert.equal(normalizeRecord(message({kind:'user'},'Current runtime context. is a phrase I want explained')).role,'user');
  assert.equal(normalizeRecord(message(undefined,'  Time sampled while preparing turn: now')),null);
  assert.equal(normalizeRecord(message(undefined,'Please explain current runtime context.')).role,'user');
  const assistant=normalizeRecord({type:'event',event:{seq:2,type:'assistant/message',data:{message:{content:[{type:'tool-call',id:'x',name:'read',arguments:'{}'},{type:'text',text:'reply'}]}}}});
  assert.equal(assistant.text,'reply');
});

test('native history and stream preserve arbitrarily long Unicode content without display truncation', () => {
  const text = '长内容😀\n'.repeat(200000);
  const history = normalizedHistory([{type:'event',event:{seq:1,type:'assistant/message',data:{message:{content:[{type:'text',text}]}}}}]);
  assert.equal(history.messages[0].text, text);
  assert.equal(history.trimmed, false);
  const snapshot = normalizeFollow({type:'snapshot',cursor:2,hasMore:true,records:[],assistantStream:{activeAttempt:{attemptId:'a',nextIndex:1,stream:[{type:'text-chunks',texts:[text]}]}}});
  assert.equal(snapshot.text, text);
  const unknown = normalizedHistory([{type:'event',event:{seq:3,type:'custom/record',data:{text}}}]);
  assert.equal(unknown.messages.length, 0, 'internal protocol events are not rendered as chat messages');
});

test('advanced native commands use exact public Session contracts and reject arbitrary RPCs', async t => {
  const {call,calls} = await setup(t);
  const operation = body => call('/pocket/api/native/operation',body);
  assert.equal((await operation({operation:'modelCatalog'})).status,200);
  assert.deepEqual(calls.at(-1).value.payload,{args:{}});
  assert.equal((await operation({operation:'rename',sessionId:'session',title:'标题'.repeat(2000)})).status,200);
  assert.equal(calls.at(-1).value.method,'session/rename');
  assert.equal((await operation({operation:'fork',sessionId:'session',atSeq:42})).status,200);
  assert.deepEqual(calls.at(-1).value.payload.args.request,{sessionId:'session',atSeq:42,allowMigration:false});
  assert.equal((await operation({operation:'selectModel',sessionId:'session',provider:'provider',model:'model',reasoningEffort:'high'})).status,200);
  assert.equal(calls.at(-1).value.payload.args.request.reasoningEffort,'high');
  assert.equal((await operation({operation:'updateQueue',sessionId:'session',itemId:'item',kind:'edit',text:'updated'})).status,200);
  assert.deepEqual(calls.at(-1).value.payload.args.request.action,{kind:'edit',content:[{type:'text',text:'updated'}]});
  assert.equal((await operation({operation:'deleteEverything',sessionId:'session'})).status,400);
  assert.equal((await operation({operation:'updateQueue',sessionId:'session',itemId:'item',kind:'edit',text:''})).status,400);
  assert.equal((await call('/pocket/api/native/prompt',{sessionId:'session',requestId:'steer',text:'adjust',mode:'steer'})).status,200);
  assert.equal(calls.at(-1).value.payload.args.request.mode,'steer');
});

async function live(t, options = {}) {
  const setupResult = await setup(t, options);
  const ws = setupResult.connect();
  const frames = [];
  ws.on('message', raw => frames.push(JSON.parse(raw)));
  await once(ws,'open');
  const until = async predicate => {
    for (let i=0;i<1000;i++) { if(predicate())return;await new Promise(resolve=>setTimeout(resolve,5)); }
    throw Error('fixture condition timed out');
  };
  await until(()=>frames.some(frame=>frame.type==='snapshot'));
  return {...setupResult,ws,frames,until};
}
test('native decisions are live, owner-bound, single-use and revoked on Host cancellation', async t => {
  const {call,calls,frames,emit,until,db} = await live(t);
  emit({type:'waterfall',event:'approval/request',eventId:'approval',agentId:'session',request:{toolName:'shell',reason:'Run command'}});
  await until(()=>frames.some(frame=>frame.type==='interaction'));
  const frame = frames.find(frame=>frame.type==='interaction');
  const answer = value => call('/pocket/api/native/answer',{connectionId:frame.connectionId,eventId:'approval',value});
  const other = randomBytes(32).toString('base64url');
  db.prepare('INSERT INTO sessions VALUES (?,?)').run(createHash('sha256').update(other).digest('hex'),Date.now()+60000);
  assert.equal((await call('/pocket/api/native/answer',{connectionId:frame.connectionId,eventId:'approval',value:'allowed-once'},'pocket='+other)).status,409);
  assert.equal((await answer('always-allow')).status,400);
  assert.equal((await answer('allowed-once')).status,200);
  assert.equal(calls.at(-1).value.method,'$events/result');
  assert.deepEqual(calls.at(-1).value.payload.args,{clientId:'client-generation',eventId:'approval',outcome:{kind:'result',value:'allowed-once'}});
  assert.equal((await answer('allowed-once')).status,409);
  emit({type:'waterfall',event:'approval/request',eventId:'cancelled',agentId:'session',request:{toolName:'shell'}});
  await until(()=>frames.some(frame=>frame.eventId==='cancelled'));
  emit({type:'cancel',eventId:'cancelled'});
  await until(()=>frames.some(frame=>frame.type==='interaction-ended'&&frame.eventId==='cancelled'));
  assert.equal((await call('/pocket/api/native/answer',{connectionId:frame.connectionId,eventId:'cancelled',value:'allowed-once'})).status,409);
});
test('native question answers validate exact IDs and choices; other scopes delegate', async t => {
  const {call,calls,frames,emit,until} = await live(t);
  emit({type:'waterfall',event:'user-questions/request',eventId:'question',agentId:'session',request:{questions:[{id:'q',question:'Choose',options:[{label:'A'},{label:'B'}]}]}});
  await until(()=>frames.some(frame=>frame.eventId==='question'));
  const frame=frames.find(frame=>frame.eventId==='question');
  const answer=answers=>call('/pocket/api/native/answer',{connectionId:frame.connectionId,eventId:'question',value:{answers}});
  assert.equal((await answer([{id:'q',selected:['forged']}])).status,400);
  assert.equal((await answer([{id:'q',selected:['A','B']}])).status,400);
  assert.equal((await answer([{id:'q',selected:['A'],custom:'details'}])).status,200);
  const before=calls.length;
  emit({type:'waterfall',event:'approval/request',eventId:'other',agentId:'other-session',request:{toolName:'shell'}});
  await until(()=>calls.length>before);
  assert.deepEqual(calls.at(-1).value.payload.args.outcome,{kind:'next'});
  assert.equal(frames.some(frame=>frame.eventId==='other'),false);
});

test('timed question claims start the deadline and user engagement preserves the wait', async t => {
  const {call,calls,frames,emit,until,openings} = await live(t);
  const request={questions:[{id:'q',question:'Choose',options:[{label:'A'}]}],wait:{timed:true,callId:'timed-call'}};
  emit({type:'waterfall',event:'user-questions/request',eventId:'timed',agentId:'session',request});
  await until(()=>frames.some(frame=>frame.eventId==='timed'));
  assert.equal(openings.at(-1).endpoint,'userQuestions/attachWait');
  const frame=frames.find(frame=>frame.eventId==='timed');
  assert.equal(frame.remainingMs,80);
  assert.equal((await call('/pocket/api/native/answer',{connectionId:frame.connectionId,eventId:'timed',engage:true})).status,200);
  await new Promise(resolve=>setTimeout(resolve,120));
  assert.equal(calls.some(call=>call.value.payload.args?.eventId==='timed'),false,'engagement pauses the local timeout');
  assert.equal((await call('/pocket/api/native/answer',{connectionId:frame.connectionId,eventId:'timed',value:{answers:[{id:'q',selected:['A']}]}})).status,200);
  emit({type:'waterfall',event:'user-questions/request',eventId:'timeout',agentId:'session',request});
  await until(()=>calls.some(call=>call.value.payload.args?.eventId==='timeout'));
  assert.equal(calls.at(-1).value.payload.args.outcome.error.code,'ASK_TIMED_OUT');
});

test('native images keep typed references and admit image-only prompts without text caps', async t => {
  const {call,calls} = await setup(t);
  const attachment={attachmentId:'a'.repeat(64),mediaType:'image/png',bytes:42,width:2,height:3,name:'example.png'};
  const content=[{type:'text',text:'image follows'},{type:'image',attachment}];
  const history=normalizedHistory([{type:'event',event:{seq:1,type:'user/message',data:{content}}}]);
  assert.deepEqual(history.messages[0].images,[attachment]);
  assert.equal((await call('/pocket/api/native/operation',{operation:'attachment',sessionId:'session',attachment})).status,200);
  assert.deepEqual(calls.at(-1).value.payload.args.request,{sessionId:'session',attachment});
  assert.equal((await call('/pocket/api/native/prompt',{sessionId:'session',requestId:'image-only',text:'',images:[{mediaType:'image/png',data:'AA==',name:'image.png'}]})).status,200);
  assert.deepEqual(calls.at(-1).value.payload.args.request.content,[{type:'image',mediaType:'image/png',data:'AA==',name:'image.png'}]);
  assert.equal((await call('/pocket/api/native/prompt',{sessionId:'session',requestId:'invalid',text:'',images:[{mediaType:'text/html',data:'AA=='}]})).status,400);
  assert.equal((await call('/pocket/api/native/prompt',{sessionId:'session',requestId:'empty',text:''})).status,400);
});

test('latest DSH raw uploads stay byte-exact and prompt emits staged file receipts', async t => {
  const {call,calls,upload,uploads}=await setup(t);
  const bytes=Buffer.from([0,1,2,3,255,65]);
  const response=await upload('/pocket/api/native/upload?sessionId=session&name=report.pdf',bytes);
  assert.equal(response.status,200);
  assert.equal(JSON.parse(response.text).value.receiptId,'receipt-1');
  assert.deepEqual(uploads[0].bytes,bytes);
  assert.equal(uploads[0].headers['content-length'],String(bytes.length));
  assert.deepEqual(uploads[0].query,{sessionId:'session',name:'report.pdf'});
  assert.equal((await call('/pocket/api/native/prompt',{sessionId:'session',requestId:'receipt-prompt',
    text:'inspect',attachments:[{type:'file',receiptId:'receipt-1'}]})).status,200);
  assert.deepEqual(calls.at(-1).value.payload.args.request.content,[
    {type:'file',receiptId:'receipt-1'},{type:'text',text:'inspect'}
  ]);
  assert.equal((await call('/pocket/api/native/prompt',{sessionId:'session',requestId:'bad-receipt',
    text:'',attachments:[{type:'file',receiptId:''}]})).status,400);
});

test('native raw uploads require and preserve an explicit byte length', async t => {
  const {upload,uploads}=await setup(t);
  const response=await upload('/pocket/api/native/upload?sessionId=session&name=missing-length',Buffer.from([1,2,3]),{
    'transfer-encoding':'chunked'
  });
  assert.equal(response.status,411);
  assert.equal(uploads.length,0);
});
test('continued question RPC uses agent scope rather than an invented request wrapper', async t => {
  const {call,calls} = await setup(t);
  const answer={answers:[{id:'q',selected:[],custom:'continue'}]};
  assert.equal((await call('/pocket/api/native/operation',{operation:'answerQuestion',sessionId:'session',callId:'call',answer})).status,200);
  assert.equal(calls.at(-1).value.method,'userQuestions/answer');
  assert.deepEqual(calls.at(-1).value.payload.args,{agent:'session',callId:'call',answer});
});

test('live transport delivers a complete Unicode record above former upstream and downstream ceilings', async t => {
  const text='内容😀'.repeat(800000);
  const {frames} = await live(t,{text});
  const snapshot=frames.find(frame=>frame.type==='snapshot');
  assert.equal(snapshot.messages[0].text,text);
  assert.equal(snapshot.messages[0].blocks[0].text,text);
});
