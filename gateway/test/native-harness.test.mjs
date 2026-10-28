import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer, request } from 'node:http';
import { randomBytes, createHash } from 'node:crypto';
import { once } from 'node:events';
import WebSocket, { WebSocketServer } from 'ws';
import { openStore } from '../src/store.mjs';
import { createApp } from '../src/app.mjs';
import { normalizeFollow, normalizedHistory, richBlocks } from '../src/native-protocol.mjs';

const origin = 'https://dsh.example.com';
async function setup(t) {
  const calls = [];
  const backend = createServer(async (req, res) => {
    const chunks = []; for await (const part of req) chunks.push(part);
    const value = JSON.parse(Buffer.concat(chunks).toString());
    calls.push({ headers: req.headers, value });
    let result;
    if (value.method === 'session/list') {
      assert.deepEqual(value.payload.args, { _request: {} }, 'source _request parameter must keep its exact wire name');
      result = { items: [{ sessionId:'session', running:true, updatedAt:42, projections:{values:{title:'Native session'}} }] };
    } else if (value.method === 'session/create') result = {sessionId:value.payload.args.request.sessionId};
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
        assert.equal(frame.payload.args.request.sessionId || frame.payload.args.request.address.sessionId,'session');
        if(frame.endpoint==='session/follow') {
          ws.send(JSON.stringify({type:'item',streamId:frame.streamId,value:{type:'snapshot',cursor:0,hasMore:false,
            records:[{type:'event',event:{seq:0,type:'user/message',data:{content:[{type:'text',text:'hello'}]}}}],
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
    const req=request({hostname:'127.0.0.1',port:server.address().port,path,method:body===undefined?'GET':'POST',headers:{host:'dsh.example.com',origin,'content-type':'application/json',...(authorized?{cookie}:{})}},res=>{
      const chunks=[];res.on('data',part=>chunks.push(part));res.on('end',()=>resolve({status:res.statusCode,text:Buffer.concat(chunks).toString()}));
    });req.on('error',reject);req.end(body===undefined?undefined:JSON.stringify(body));
  });
  const connect=(headers={})=>new WebSocket(`ws://127.0.0.1:${server.address().port}/pocket/native/live?sessionId=session`,{headers:{Host:'dsh.example.com',Origin:origin,Cookie:cookie,...headers}});
  return {call,calls,connect,openings,db};
}

test('native adapter uses official RPC envelopes and keeps upstream credentials server-side',async t=>{
  const {call,calls}=await setup(t);
  assert.equal((await call('/pocket/api/native/sessions',undefined,false)).status,401);
  const sessions=await call('/pocket/api/native/sessions');
  assert.equal(sessions.status,200);
  assert.deepEqual(JSON.parse(sessions.text),{protocol:1,truncated:false,items:[{id:'session',title:'Native session',running:true,updatedAt:42}]});
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
  assert.deepEqual(openings.map(frame=>frame.endpoint),['session/follow','session/observeState']);
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

test('native history and stream preserve arbitrarily long Unicode content without display truncation', () => {
  const text = '长内容😀\n'.repeat(200000);
  const history = normalizedHistory([{type:'event',event:{seq:1,type:'assistant/message',data:{message:{content:[{type:'text',text}]}}}}]);
  assert.equal(history.messages[0].text, text);
  assert.equal(history.trimmed, false);
  const snapshot = normalizeFollow({type:'snapshot',cursor:2,hasMore:true,records:[],assistantStream:{activeAttempt:{attemptId:'a',nextIndex:1,stream:[{type:'text-chunks',texts:[text]}]}}});
  assert.equal(snapshot.text, text);
  const unknown = normalizedHistory([{type:'event',event:{seq:3,type:'custom/record',data:{text}}}]);
  assert.equal(JSON.parse(unknown.messages[0].text).text, text);
});
