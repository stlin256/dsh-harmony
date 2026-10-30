const fullText = value => typeof value === 'string' ? value : value === undefined || value === null ? '' : JSON.stringify(value);
export const sessionIdValid = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,160}$/.test(value);
export function textBlocks(content) {
  if (typeof content === 'string') return { text: fullText(content), reasoning: '' };
  const blocks = Array.isArray(content) ? content : [];
  const text = [], reasoning = [];
  for (const block of blocks) {
    if (block?.type === 'text') text.push(fullText(block.text));
    else if (block?.type === 'reasoning') reasoning.push(fullText(block.text));
    else if (block?.type === 'image' || block?.type === 'tool-call') continue;
    else text.push(fullText(block));
  }
  return { text: fullText(text.join('\n')), reasoning: fullText(reasoning.join('\n')) };
}
function textRuns(text) {
  return text.split(/\n\s*\n/).filter(part => part.trim()).map(part => {
    const heading = /^(#{1,4})\s+(.+)$/.exec(part.trim());
    if (heading) return { kind: 'heading', text: heading[2], language: '' };
    if (part.split('\n').every(line => /^>\s?/.test(line))) return { kind: 'quote', text: part.replace(/^>\s?/gm, ''), language: '' };
    return { kind: 'text', text: part.replace(/^[-*]\s+/gm, '• '), language: '' };
  });
}
export function richBlocks(text) {
  const result = [];
  const pattern = /```([^\n`]*)\n([\s\S]*?)```/g;
  let previous = 0;
  for (const match of text.matchAll(pattern)) {
    if (match.index > previous) result.push(...textRuns(text.slice(previous, match.index)));
    result.push({ kind: 'code', text: match[2], language: fullText(match[1].trim(), 30) });
    previous = match.index + match[0].length;
  }
  if (previous < text.length) result.push(...textRuns(text.slice(previous)));
  return result;
}
export function normalizeRecord(record) {
  const event = record?.event;
  if (record?.type !== 'event' || !event || !Number.isSafeInteger(event.seq)) return null;
  const data = event.data || {};
  let role, label, content, detail = '';
  const source = data.source || data.message?.source;
  const sourceKind = typeof source?.kind === 'string' ? source.kind : '';
  if (event.type === 'user/message') {
    content = textBlocks(data.content);
    if (sourceKind && !['user', 'client', 'steer'].includes(sourceKind)) return null;
    if (!sourceKind && /^(?:current runtime context\.|time sampled while preparing turn|browser time zone for this request:|elapsed since the preceding model-visible message:|current working directory:|current dsh file policy:|<system[-_]reminder>)/i.test(content.text.trimStart())) return null;
    role = 'user'; label = '你';
  }
  else if (event.type === 'assistant/message') { role = 'assistant'; label = 'DeepSeek'; content = textBlocks(data.message?.content); }
  else if (event.type === 'tool/call') { role = 'tool'; label = '工具 · ' + fullText(data.name, 100); content = { text: fullText(data.arguments), reasoning: '' }; }
  else if (event.type === 'tool/result') { role = 'tool'; label = data.message?.isError ? '工具执行失败' : '工具结果'; content = textBlocks(data.message?.content); }
  else if (event.type === 'tool/ptc-dispatch-start' || event.type === 'tool/ptc-dispatch') {
    role = 'tool'; label = fullText(data.name); content = event.type.endsWith('-start') ? { text: fullText(data.arguments), reasoning: '' } : textBlocks(data.content);
  }
  else if (event.type === 'command/run' || event.type === 'command/done') {
    role = 'tool'; label = '/' + fullText(data.name); content = { text: fullText(event.type === 'command/run' ? data.args : data.text), reasoning: '' };
  }
  else if (event.type === 'turn/start' || event.type === 'turn/end') {
    role = 'turn'; label = event.type === 'turn/start' ? '进行中' : data.reason?.kind === 'error' ? '执行失败' : data.reason?.kind === 'cancelled' ? '已停止' : '已完成';
    content = { text: event.type === 'turn/end' && data.reason?.kind === 'error' ? fullText(data.reason.error?.message || '任务执行失败') : '', reasoning: '' };
  }
  else if (event.type === 'step/end') { role = 'boundary'; label = ''; content = { text: '', reasoning: '' }; }
  else if (event.type === 'approval/asked') { role = 'notice'; label = '等待确认'; content = { text: '', reasoning: '' }; }
  else return null;
  const parts = event.type === 'user/message' ? data.content : event.type === 'assistant/message' || event.type === 'tool/result' ? data.message?.content : [];
  const images = Array.isArray(parts) ? parts.filter(part => part?.type === 'image' && part.attachment).map(part => part.attachment) : [];
  const segments = role === 'assistant' && Array.isArray(parts) ? parts.flatMap(part => {
    if (part?.type === 'text' || part?.type === 'reasoning') return [{ kind: part.type, text: fullText(part.text), blocks: richBlocks(fullText(part.text)), images: [] }];
    if (part?.type === 'image' && part.attachment) return [{ kind: 'image', text: '', blocks: [], images: [part.attachment] }];
    return [];
  }) : [];
  const callId = data.callId ?? data.subCallId ?? data.message?.source?.callId ?? data.commandId;
  return { images, id: 'event-' + event.seq, seq: event.seq, role, label, text: content.text, reasoning: content.reasoning,
    metaRaw: JSON.stringify(data.message?.meta ?? data.meta ?? null), contentRaw: JSON.stringify(parts || []),
    errorRaw: JSON.stringify(data.message?.error ?? data.error ?? null),
    blocks: richBlocks(content.text), segments, detail, eventType: event.type, sourceKind,
    turn: Number.isSafeInteger(data.turn) ? data.turn : -1, step: Number.isSafeInteger(data.step) ? data.step : -1,
    time: Number.isFinite(event.time) ? event.time : 0, callId: callId == null ? '' : String(callId),
    parentCallId: fullText(data.parentCallId), rootCallId: fullText(data.rootCallId), toolName: fullText(data.name),
    phase: /(?:tool\/call|dispatch-start|command\/run)$/.test(event.type) ? 'start' : 'result',
    failed: data.message?.isError === true || data.isError === true || data.kind === 'error',
    outcome: fullText(data.reason?.kind), error: fullText(data.error?.message || data.error?.reason || '') };
}
export function normalizedHistory(records) {
  let messages = [];
  for (const record of Array.isArray(records) ? records : []) {
    const op = record?.event?.surfaceOp;
    if (op?.op === 'replace') messages = messages.filter(row => row.seq < op.startSeq || row.seq > op.endSeq);
    const row = normalizeRecord(record);
    if (row) messages.push(row);
  }
  return { messages, journal: (records || []).filter(record => record?.type === 'event' && Number.isSafeInteger(record.event?.seq))
    .map(record => ({ seq: record.event.seq, raw: JSON.stringify(record.event) })), trimmed: false, replacements: (records || []).map(record => record.event?.surfaceOp)
    .filter(op => op?.op === 'replace').map(op => ({ start: op.startSeq, end: op.endSeq })) };
}
export function compactText(stream) {
  let text = '', reasoning = '';
  const toolUpdates = [];
  for (const record of Array.isArray(stream) ? stream : []) {
    if (record?.type === 'text-chunks') text += (record.texts || []).join('');
    if (record?.type === 'reasoning-chunks') reasoning += (record.texts || []).join('');
    if (record?.type === 'chunk' && record.chunk?.type === 'text-delta') text += record.chunk.text;
    if (record?.type === 'chunk' && record.chunk?.type === 'reasoning-delta') reasoning += record.chunk.text;
    if (record?.type === 'chunk') { const update = toolUpdate(record.chunk); if (update) toolUpdates.push(update); }
  }
  return { text: fullText(text), reasoning: fullText(reasoning), ...(toolUpdates.length ? { toolUpdates } : {}) };
}
function toolUpdate(chunk) {
  if (chunk?.type === 'tool-call-delta') return { callId: String(chunk.id), name: fullText(chunk.name), argsDelta: fullText(chunk.argumentsDelta), arguments: '', replace: false };
  if (chunk?.type === 'block-end' && chunk.block?.type === 'tool-call') return { callId: String(chunk.block.id), name: fullText(chunk.block.name), argsDelta: '', arguments: fullText(chunk.block.arguments), replace: true };
  return null;
}
export function normalizeFollow(frame) {
  if (frame?.type === 'snapshot') {
    const history = normalizedHistory(frame.records);
    const active = frame.assistantStream?.activeAttempt;
    return { type: 'snapshot', ...history, cursor: frame.cursor, hasMore: frame.hasMore === true, beforeSeq: frame.records?.[0]?.event?.seq ?? 0,

      attemptId: active?.attemptId || '', nextIndex: active?.nextIndex || 0, ...compactText(active?.stream) };
  }
  if (frame?.type === 'event') {
    const op = frame.event?.surfaceOp;
    return { type: 'event', seq: frame.event?.seq, message: normalizeRecord(frame),
      journal: Number.isSafeInteger(frame.event?.seq) ? [{ seq: frame.event.seq, raw: JSON.stringify(frame.event) }] : [],
      replaceStart: op?.op === 'replace' ? op.startSeq : -1, replaceEnd: op?.op === 'replace' ? op.endSeq : -1 };
  }
  if (frame?.type === 'assistant-stream') {
    const item = frame.frame;
    if (item?.type === 'start') return { type: 'start', attemptId: item.attemptId, nextIndex: 0 };
    if (item?.type === 'chunk') return { type: 'delta', attemptId: item.attemptId, index: item.index,
      text: item.chunk?.type === 'text-delta' ? fullText(item.chunk.text) : '',
      reasoning: item.chunk?.type === 'reasoning-delta' ? fullText(item.chunk.text) : '',
      ...(toolUpdate(item.chunk) ? { toolUpdates: [toolUpdate(item.chunk)] } : {}) };
    if (item?.type === 'end') return { type: 'end', attemptId: item.attemptId };
  }
  return null;
}
