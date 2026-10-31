import { NativeMessage } from './NativeSessionModel';

export class NativePlanItem {
  content: string = '';
  status: string = 'pending';
}

export class NativePlanDocument {
  parsed: boolean = false;
  items: NativePlanItem[] = [];
}

class NativePlanPayload {
  recognized: boolean = false;
  items: NativePlanItem[] = [];
}

function planArray(value: Object): Object[] | null {
  if (Array.isArray(value)) return value as Object[];
  if (!value || typeof value !== 'object') return null;
  const record = value as Record<string, Object>;
  let candidate: Object | undefined = undefined;
  if (record['todos'] !== undefined) candidate = record['todos'];
  else if (record['items'] !== undefined) candidate = record['items'];
  else if (record['plan'] !== undefined) candidate = record['plan'];
  return candidate !== undefined && Array.isArray(candidate) ? candidate as Object[] : null;
}

function parsePlan(value: string): NativePlanPayload {
  const payload = new NativePlanPayload();
  if (!value.trim()) return payload;
  try {
    const candidates = planArray(JSON.parse(value) as Object);
    if (candidates === null) return payload;
    payload.recognized = true;
    candidates.forEach((raw: Object): void => {
      if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return;
      const record = raw as Record<string, Object>;
      const contentValue = record['content'] ?? record['text'] ?? record['title'];
      const content = typeof contentValue === 'string' ? contentValue.trim() : '';
      if (!content) return;
      const statusValue = record['status'];
      const rawStatus = typeof statusValue === 'string' ? statusValue : 'pending';
      const item = new NativePlanItem();
      item.content = content;
      item.status = ['completed', 'in_progress', 'pending'].includes(rawStatus) ? rawStatus : 'pending';
      payload.items.push(item);
    });
  } catch (_) {
    // Streaming and malformed payloads remain inert presentation data.
  }
  return payload;
}

/**
 * Project the official todo_write payload into a read-only presentation model.
 * A later repeated payload in output is accepted for older Host versions.
 */
export function nativePlanDocument(tool: NativeMessage): NativePlanDocument {
  const document = new NativePlanDocument();
  const sources: string[] = [tool.args, tool.output];
  for (const source of sources) {
    const payload = parsePlan(source);
    if (!payload.recognized) continue;
    document.parsed = true;
    document.items = payload.items;
    return document;
  }
  return document;
}

/** Select the newest complete todo_write update from a projected transcript. */
export function nativeLatestPlan(rows: NativeMessage[]): NativePlanDocument {
  let latest = new NativePlanDocument();
  const visit = (row: NativeMessage): void => {
    if (row.role === 'tool' && row.toolName === 'todo_write') {
      const candidate = nativePlanDocument(row);
      if (candidate.parsed) latest = candidate;
    }
    row.children.forEach(visit);
  };
  rows.forEach(visit);
  return latest;
}

export function nativePlanProgress(document: NativePlanDocument): string {
  let completed = 0;
  let active = 0;
  let pending = 0;
  document.items.forEach((item: NativePlanItem): void => {
    if (item.status === 'completed') completed++;
    else if (item.status === 'in_progress') active++;
    else pending++;
  });
  const parts: string[] = [];
  if (completed) parts.push('已完成 ' + completed);
  if (active) parts.push('进行中 ' + active);
  if (pending) parts.push('待处理 ' + pending);
  return parts.join(' · ');
}

/**
 * Compare complete todo lists by content. A newly created completed item counts
 * as created; completed is reserved for an existing item reaching that state.
 */
export function nativePlanDiff(current: NativePlanDocument, previous: NativePlanDocument): string {
  const previousStatuses: Map<string, string> = new Map<string, string>();
  const currentContents: Set<string> = new Set<string>();
  previous.items.forEach((item: NativePlanItem): void => {
    previousStatuses.set(item.content, item.status);
  });
  let created = 0;
  let completed = 0;
  let updated = 0;
  current.items.forEach((item: NativePlanItem): void => {
    currentContents.add(item.content);
    const before = previousStatuses.get(item.content);
    if (before === undefined) {
      created++;
    } else if (before !== item.status) {
      if (item.status === 'completed') completed++;
      else updated++;
    }
  });
  let removed = 0;
  previous.items.forEach((item: NativePlanItem): void => {
    if (!currentContents.has(item.content)) removed++;
  });
  const parts: string[] = [];
  if (created) parts.push('创建 ' + created);
  if (completed) parts.push('完成 ' + completed);
  if (updated) parts.push('更新 ' + updated);
  if (removed) parts.push('移除 ' + removed);
  return parts.length ? parts.join(' · ') : '无变化';
}

export function nativePlanSignature(document: NativePlanDocument): string {
  return document.items.map((item: NativePlanItem): string =>
    item.status + '\n' + item.content).join('\n\u0000\n');
}
