import { NativeMessage, NativeAssistantSegment } from './NativeSessionModel';
import { NativeChatPreferences } from './NativeHostSettings';

// Mirrors Chat's event projection, call-id lifecycle, process boundaries and exact tool-name categories.
export function nativeToolCategory(name: string): string {
  if (name === 'read') return 'read';
  if (name === 'read_image') return 'readImage';
  if (name === 'grep' || name === 'glob' || name.endsWith('_inspect')) return 'search';
  if (name === 'write') return 'write';
  if (name === 'edit' || name === 'apply_patch') return 'edit';
  if (['bash', 'pwsh', 'exec_command', 'write_stdin'].includes(name) || name.startsWith('terminal_')) return 'commands';
  if (name === 'run_code') return 'code';
  if (name === 'web_search') return 'webSearch';
  if (name === 'web_fetch') return 'webFetch';
  if (name === 'subagent' || name.startsWith('subagent_')) return 'subagents';
  if (['todo_write', 'create_goal', 'update_goal', 'get_goal'].includes(name)) return 'plan';
  if (['ask_user_question', 'request_user_input'].includes(name)) return 'questions';
  return 'tools';
}
export function nativeActivity(category: string, running: boolean): string {
  const kinds = ['read', 'readImage', 'search', 'write', 'edit', 'commands', 'code', 'webSearch', 'webFetch', 'subagents', 'plan', 'questions', 'tools'];
  const active = ['正在读取文件', '正在读取图片', '正在搜索代码', '正在写入文件', '正在编辑文件', '正在运行命令', '正在运行代码', '正在搜索网页', '正在访问网页', '正在协调子代理', '正在更新计划', '等待你的操作', '正在调用工具'];
  const settled = ['已读取文件', '已读取图片', '已搜索代码', '已写入文件', '修改了文件', '执行了命令', '运行了代码', '已搜索网页', '已访问网页', '已协调子代理', '更新了计划', '向用户提出了问题', '已调用工具'];
  const index = kinds.indexOf(category);
  return index < 0 ? running ? '正在分析请求' : '已完成分析' : (running ? active : settled)[index];
}
export function nativeProcessIcon(category: string): string {
  if (category === 'read' || category === 'readImage' || category === 'webFetch') return 'browse-outline';
  if (category === 'search') return 'search-outline';
  if (category === 'edit' || category === 'write') return 'edit-outline';
  if (category === 'commands') return 'api-outline';
  if (category === 'code') return 'code-outline';
  if (category === 'webSearch') return 'globe-outline';
  if (category === 'subagents') return 'agent-preset-outline';
  if (category === 'plan') return 'plan-outline';
  if (category === 'questions') return 'question-outline';
  return category === 'tools' ? 'sparkle' : 'think-outline';
}
export function nativeToolDetail(tool: NativeMessage): string {
  const fields = ['title', 'description', 'objective', 'task', 'task_name', 'name', 'question', 'questions', 'prompt', 'message', 'command', 'cmd', 'queries', 'query', 'pattern', 'url', 'uri', 'file_path', 'path', 'target', 'action', 'status'];
  let values: Record<string, Object> = {};
  try { values = JSON.parse(tool.args) as Record<string, Object>; } catch (_) {}
  for (const field of fields) {
    const value = values?.[field];
    let text = typeof value === 'string' ? value : '';
    if (Array.isArray(value) && value.every((part: Object) => typeof part === 'string')) text = (value as string[]).join(', ');
    if (field === 'questions' && Array.isArray(value)) {
      const questions = value as Record<string, Object>[];
      const first = questions.find((part: Record<string, Object>) => typeof part?.question === 'string' && (part.question as string).trim().length > 0);
      if (first) text = first.question as string;
    }
    if (!text && tool.phase === 'preparing') {
      const match = new RegExp('"' + field + '"\\s*:\\s*"((?:\\\\.|[^"\\\\])*)').exec(tool.args);
      if (match) { try { text = JSON.parse('"' + match[1] + '"') as string; } catch (_) {} }
    }
    text = text.replace(/\s+/g, ' ').trim();
    if (text) return text.length > 160 ? text.slice(0, 159) + '…' : text;
  }
  return tool.phase === 'preparing' ? '' : tool.toolName;
}
function copy(value: NativeMessage): NativeMessage {
  const row = new NativeMessage();
  row.id = value.id; row.seq = value.seq; row.role = value.role; row.label = value.label || '';
  row.text = value.text || ''; row.reasoning = value.reasoning || ''; row.blocks = value.blocks || []; row.images = value.images || [];
  row.eventType = value.eventType || ''; row.turn = value.turn ?? -1; row.step = value.step ?? -1; row.time = value.time || 0;
  row.callId = value.callId || ''; row.parentCallId = value.parentCallId || ''; row.rootCallId = value.rootCallId || '';
  row.toolName = value.toolName || ''; row.phase = value.phase || ''; row.failed = value.failed === true;
  row.outcome = value.outcome || ''; row.error = value.error || ''; row.sourceKind = value.sourceKind || '';
  row.turnKey = value.turnKey || '';
  row.metaRaw = value.metaRaw || ''; row.contentRaw = value.contentRaw || ''; row.errorRaw = value.errorRaw || '';
  return row;
}
function visit(calls: NativeMessage[], fn: (tool: NativeMessage) => void, seen: Set<string> = new Set<string>()): void {
  const pending = calls.slice().reverse();
  while (pending.length) {
    const call = pending.pop() as NativeMessage;
    if (seen.has(call.id)) continue;
    seen.add(call.id); fn(call); pending.push(...call.children.slice().reverse());
  }
}
export function nativeProcessTitle(group: NativeMessage, showDetail: boolean = true): string {
  const active: NativeMessage[] = [];
  const counts: Map<string, number> = new Map<string, number>();
  visit(group.children, (tool: NativeMessage): void => {
    if (tool.role !== 'tool') return;
    const category = nativeToolCategory(tool.toolName);
    counts.set(category, (counts.get(category) || 0) + 1);
    if (tool.status === 'running' || tool.status === 'preparing') active.push(tool);
  });
  if (!group.closed) {
    if (!active.length) { group.toolName = 'thinking'; return '正在分析请求'; }
    const latest = active.sort((a: NativeMessage, b: NativeMessage) => a.time - b.time)[active.length - 1];
    group.toolName = nativeToolCategory(latest.toolName);
    const detail = nativeToolDetail(latest);
    return nativeActivity(nativeToolCategory(latest.toolName), true) + (showDetail && detail ? ' · ' + detail : '');
  }
  const ranked: string[] = Array.from(counts.keys()).sort((a: string, b: string) => (counts.get(b) || 0) - (counts.get(a) || 0));
  group.toolName = ranked[0] || 'thinking';
  const labels = ranked.slice(0, 3).map((category: string) => nativeActivity(category, false));
  if (!labels.length) return '已完成分析';
  if (labels.length === 2) return labels[0] + '并' + (labels[0].startsWith('已') && labels[1].startsWith('已') ? labels[1].slice(1) : labels[1]);
  return labels.join('，') + (ranked.length > 3 ? '等' : '');
}

export function nativeTranscript(records: NativeMessage[], running: boolean, streamTools: NativeMessage[] = [], reasoning: string = '', text: string = ''): NativeMessage[] {
  const calls: Map<string, NativeMessage> = new Map<string, NativeMessage>();
  const ordered: NativeMessage[] = [];
  const ends: Map<string, NativeMessage> = new Map<string, NativeMessage>();
  const starts: Map<string, number> = new Map<string, number>();
  const closedSteps: Set<string> = new Set<string>();
  let turnKey = 'legacy:0';
  for (const input of records) {
    const row = copy(input);
    if (row.turn >= 0) turnKey = 'turn:' + row.turn;
    else if (row.role === 'user') turnKey = 'legacy:' + row.seq;
    row.turnKey = turnKey;
    if (row.role === 'detail' || (row.role === 'user' && row.sourceKind && !['user', 'client', 'steer'].includes(row.sourceKind))) continue;
    if (row.role === 'turn') {
      if (row.eventType === 'turn/start') starts.set(turnKey, row.time);
      else ends.set(turnKey, row);
      ordered.push(row); continue;
    }
    if (row.role === 'boundary') { closedSteps.add(turnKey + ':' + row.step); continue; }
    if (row.role === 'tool') {
      const id = row.callId || row.id;
      let tool = calls.get(id);
      if (!tool) {
        tool = row; tool.id = 'call:' + id; tool.children = []; tool.args = ''; tool.output = '';
        calls.set(id, tool); ordered.push(tool);
      }
      if (row.toolName) tool.toolName = row.toolName;
      if (row.parentCallId) tool.parentCallId = row.parentCallId;
      if (row.rootCallId) tool.rootCallId = row.rootCallId;
      if (row.phase === 'start' || row.phase === 'preparing') {
        tool.args = row.text; tool.status = row.phase === 'preparing' ? 'preparing' : 'running'; tool.phase = row.phase; tool.time = row.time;
      } else {
        tool.output = row.text; tool.failed = row.failed; tool.status = row.failed ? 'error' : 'success'; tool.phase = 'result'; tool.error = row.error;
        tool.images = row.images; tool.metaRaw = row.metaRaw; tool.contentRaw = row.contentRaw; tool.errorRaw = row.errorRaw;
      }
      continue;
    }
    if (row.role === 'assistant' && input.segments?.length) {
      input.segments.forEach((segment: NativeAssistantSegment, index: number): void => {
        if (!segment.text.trim() && !segment.images.length) return;
        const part = copy(row); part.id = row.id + ':part:' + index; part.text = segment.kind === 'reasoning' ? '' : segment.text;
        part.reasoning = segment.kind === 'reasoning' ? segment.text : ''; part.role = segment.kind === 'reasoning' ? 'reasoning' : 'assistant';
        part.blocks = segment.kind === 'reasoning' ? [] : segment.blocks; part.images = segment.images;
        ordered.push(part);
      });
      continue;
    }
    if (row.role === 'assistant' && row.reasoning.trim()) {
      const thought = copy(row); thought.id = 'reason:' + row.id; thought.role = 'reasoning'; thought.text = ''; thought.blocks = []; thought.images = [];
      ordered.push(thought); row.reasoning = '';
    }
    if (row.text.trim() || row.images.length) ordered.push(row);
  }
  for (const preparing of streamTools) {
    if (calls.has(preparing.callId)) continue;
    const tool = copy(preparing); tool.args = tool.text; tool.status = 'preparing'; tool.turnKey = turnKey;
    tool.id = 'call:' + tool.callId; calls.set(tool.callId, tool); ordered.push(tool);
  }
  if (reasoning.trim()) {
    const thought = new NativeMessage(); thought.id = 'live-reasoning'; thought.role = 'reasoning'; thought.reasoning = reasoning; thought.turnKey = turnKey;
    ordered.push(thought);
  }
  if (text.trim()) {
    const reply = new NativeMessage(); reply.id = 'live-assistant'; reply.role = 'assistant'; reply.text = text; reply.turnKey = turnKey;
    ordered.push(reply);
  }
  for (const tool of calls.values()) {
    if (tool.status === 'running' && (ends.has(tool.turnKey) || closedSteps.has(tool.turnKey + ':' + tool.step))) tool.status = 'interrupted';
    if (tool.parentCallId) {
      const parent = calls.get(tool.parentCallId) || calls.get(tool.rootCallId);
      let cursor = parent;
      const ancestors: Set<string> = new Set<string>();
      while (cursor && cursor !== tool && !ancestors.has(cursor.id)) {
        ancestors.add(cursor.id); cursor = calls.get(cursor.parentCallId);
      }
      if (parent && !cursor) parent.children.push(tool);
      else { tool.parentCallId = ''; tool.rootCallId = ''; }
    }
  }
  const rows: NativeMessage[] = [];
  let group: NativeMessage | null = null;
  const flush = (closed: boolean): void => {
    if (!group) return;
    group.closed = closed; group.label = nativeProcessTitle(group); rows.push(group); group = null;
  };
  for (const row of ordered) {
    if (row.role === 'tool' && row.parentCallId && (calls.has(row.parentCallId) || calls.has(row.rootCallId))) continue;
    if (row.role === 'tool' || row.role === 'reasoning' || row.role === 'notice') {
      if (group && group.turnKey !== row.turnKey) flush(true);
      if (!group) { group = new NativeMessage(); group.id = 'process:' + row.id; group.role = 'process'; group.turnKey = row.turnKey; }
      group.children.push(row); continue;
    }
    flush(true);
    if (row.role !== 'turn' || row.eventType !== 'turn/start') rows.push(row);
  }
  flush(!running || ends.has(turnKey));
  const foldable: Set<string> = new Set<string>();
  ends.forEach((end: NativeMessage, key: string): void => {
    const firstProcess = rows.findIndex((row: NativeMessage) => row.turnKey === key && row.role === 'process');
    const inputAfterProcess = firstProcess >= 0 && rows.slice(firstProcess + 1).some((row: NativeMessage) => row.turnKey === key && row.role === 'user');
    if (firstProcess >= 0 && !inputAfterProcess && end.outcome === 'completed') foldable.add(key);
  });
  const result: NativeMessage[] = [];
  const controls: Set<string> = new Set<string>();
  for (const row of rows) {
    if (row.role === 'process' && foldable.has(row.turnKey)) {
      row.foldable = true;
      if (!controls.has(row.turnKey)) {
        const control = new NativeMessage(); control.id = 'turn-control:' + row.turnKey; control.role = 'turn-control'; control.turnKey = row.turnKey;
        const end = ends.get(row.turnKey); const start = starts.get(row.turnKey) || 0;
        control.label = start > 0 && end && end.time >= start ? '工作过程 · ' + Math.round((end.time - start) / 1000) + ' 秒' : '工作过程';
        result.push(control); controls.add(row.turnKey);
      }
    }
    if (row.role === 'turn') row.role = 'turn-footer';
    result.push(row);
  }
  return result;
}

/** Presentation policy is independent from event pairing and does not mutate durable records. */
export function nativePresentTranscript(rows: NativeMessage[], preferences: NativeChatPreferences,
  manual: Map<string, boolean>, collapseThrough: number = -1): NativeMessage[] {
  const ended: Set<string> = new Set<string>();
  const lastReply: Map<string, number> = new Map<string, number>();
  const endSeq: Map<string, number> = new Map<string, number>();
  let exchange = '';
  for (const row of rows) {
    if (row.role === 'turn-footer') { ended.add(row.turnKey); endSeq.set(row.turnKey, row.seq); }
    if (row.role === 'assistant') lastReply.set(row.turnKey, row.seq);
    if (row.role === 'user' && row.sourceKind !== 'steer') exchange = row.turnKey;
  }
  const exchangeIndex = rows.findIndex((row: NativeMessage) => row.turnKey === exchange);
  const deferred: Set<string> = new Set<string>();
  if (preferences.collapseTiming === 'next-input') {
    rows.forEach((row: NativeMessage, index: number): void => {
      if (index >= Math.max(0, exchangeIndex) && (endSeq.get(row.turnKey) || 0) > collapseThrough) deferred.add(row.turnKey);
    });
  }
  const open = (key: string): boolean => preferences.mode === 'verbose' || (manual.has(key) ? manual.get(key) === true : deferred.has(key));
  return rows.filter((row: NativeMessage): boolean => {
    if (row.role === 'turn-control') { row.foldable = preferences.mode !== 'verbose'; return true; }
    if (row.role === 'process') {
      row.runningTurn = !ended.has(row.turnKey) || deferred.has(row.turnKey);
      row.flat = preferences.mode === 'verbose' || (preferences.mode === 'detailed' && row.runningTurn);
      row.preview = preferences.mode !== 'compact';
      row.label = nativeProcessTitle(row, preferences.mode !== 'compact');
      return !row.foldable || open(row.turnKey);
    }
    if (row.role === 'assistant' && preferences.foldedReplies === 'final' &&
      rows.some((item: NativeMessage) => item.turnKey === row.turnKey && item.role === 'turn-control') && row.seq !== lastReply.get(row.turnKey)) return open(row.turnKey);
    return true;
  });
}

export function nativeReasoningPreview(text: string, running: boolean): string {
  const value = text.trimStart();
  if (!running) return (value.split('\n')[0] || '').replace(/\*\*/g, '').trim();
  // A complete first line is required; later deltas do not animate an unfinished preview.
  const lines = value.split('\n');
  if (lines.length < 2) return '';
  let first = '';
  for (let index = 0; index < lines.length - 1; index++) {
    if (index === 0 || !lines[index - 1].trim()) { if (lines[index].trim()) first = lines[index]; }
  }
  return first.replace(/\*\*/g, '').trim();
}
