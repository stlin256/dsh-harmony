const clipped = (value, limit = 24000) => typeof value === 'string' ? value.length > limit ? value.slice(0, limit) + '\n…内容已截断，请在兼容模式查看完整内容' : value : '';
export const sessionIdValid = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,160}$/.test(value);
export function textBlocks(content) {
  if (typeof content === 'string') return { text: clipped(content), reasoning: '' };
  const blocks = Array.isArray(content) ? content : [];
  const text = [], reasoning = [];
  for (const block of blocks) {
    if (block?.type === 'text') text.push(clipped(block.text));
    else if (block?.type === 'reasoning') reasoning.push(clipped(block.text));
    else if (block?.type === 'image') text.push('[图片：请在兼容模式查看]');
    else if (block?.type === 'tool-call') text.push('[工具调用 ' + clipped(block.name, 120) + ']');
    else text.push('[此内容请在兼容模式查看]');
  }
  return { text: clipped(text.join('\n')), reasoning: clipped(reasoning.join('\n')) };
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
    result.push({ kind: 'code', text: match[2], language: clipped(match[1].trim(), 30) });
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
  if (event.type === 'user/message') { role = 'user'; label = '你'; content = textBlocks(data.content); }
  else if (event.type === 'assistant/message') { role = 'assistant'; label = 'DeepSeek'; content = textBlocks(data.message?.content); }
  else if (event.type === 'tool/call') { role = 'tool'; label = '工具 · ' + clipped(data.name, 100); content = { text: clipped(data.arguments), reasoning: '' }; }
  else if (event.type === 'tool/result') { role = 'tool'; label = data.message?.isError ? '工具执行失败' : '工具结果'; content = textBlocks(data.message?.content); }
  else if (event.type === 'approval/asked') { role = 'notice'; label = '需要审批'; content = { text: '请切换到兼容模式处理此审批。', reasoning: '' }; }
  else if (event.type === 'turn/end' && data.reason?.kind === 'error') { role = 'notice'; label = '执行失败'; content = { text: clipped(data.reason.error?.message || '请检查服务端配置后重试'), reasoning: '' }; }
  else return null;
  return { id: 'event-' + event.seq, seq: event.seq, role, label, text: content.text, reasoning: content.reasoning,
    blocks: richBlocks(content.text), detail };
}
export function normalizedHistory(records) {
  let messages = [];
  for (const record of Array.isArray(records) ? records : []) {
    const op = record?.event?.surfaceOp;
    if (op?.op === 'replace') messages = messages.filter(row => row.seq < op.startSeq || row.seq > op.endSeq);
    const row = normalizeRecord(record);
    if (row) messages.push(row);
  }
  let bytes = 0;
  const bounded = [];
  for (const row of messages.slice().reverse()) {
    bytes += Buffer.byteLength(JSON.stringify(row));
    if (bytes > 750000) break;
    bounded.unshift(row);
  }
  return { messages: bounded, trimmed: bounded.length !== messages.length };
}
export function compactText(stream) {
  let text = '', reasoning = '';
  for (const record of Array.isArray(stream) ? stream : []) {
    if (record?.type === 'text-chunks') text += (record.texts || []).join('');
    if (record?.type === 'reasoning-chunks') reasoning += (record.texts || []).join('');
    if (record?.type === 'chunk' && record.chunk?.type === 'text-delta') text += record.chunk.text;
    if (record?.type === 'chunk' && record.chunk?.type === 'reasoning-delta') reasoning += record.chunk.text;
  }
  return { text: clipped(text), reasoning: clipped(reasoning) };
}
export function normalizeFollow(frame) {
  if (frame?.type === 'snapshot') {
    const history = normalizedHistory(frame.records);
    const active = frame.assistantStream?.activeAttempt;
    return { type: 'snapshot', ...history, cursor: frame.cursor, hasMore: frame.hasMore || history.trimmed,
      attemptId: active?.attemptId || '', nextIndex: active?.nextIndex || 0, ...compactText(active?.stream) };
  }
  if (frame?.type === 'event') {
    const op = frame.event?.surfaceOp;
    return { type: 'event', seq: frame.event?.seq, message: normalizeRecord(frame),
      replaceStart: op?.op === 'replace' ? op.startSeq : -1, replaceEnd: op?.op === 'replace' ? op.endSeq : -1 };
  }
  if (frame?.type === 'assistant-stream') {
    const item = frame.frame;
    if (item?.type === 'start') return { type: 'start', attemptId: item.attemptId, nextIndex: 0 };
    if (item?.type === 'chunk') return { type: 'delta', attemptId: item.attemptId, index: item.index,
      text: item.chunk?.type === 'text-delta' ? clipped(item.chunk.text) : '',
      reasoning: item.chunk?.type === 'reasoning-delta' ? clipped(item.chunk.text) : '' };
    if (item?.type === 'end') return { type: 'end', attemptId: item.attemptId };
  }
  return null;
}
