export class NativeTextBlock {
  kind: string = 'text';
  text: string = '';
  language: string = '';
}
export class NativeImageAttachment {
  attachmentId: string = ''; mediaType: string = ''; bytes: number = 0;
  width: number = 0; height: number = 0; name: string = '';
}
export class NativeAssistantSegment {
  kind: string = ''; text: string = ''; blocks: NativeTextBlock[] = []; images: NativeImageAttachment[] = [];
}
export class NativeMessage {
  metaRaw: string = ''; contentRaw: string = ''; errorRaw: string = '';
  flat: boolean = false; preview: boolean = true; runningTurn: boolean = false;
  segments: NativeAssistantSegment[] = [];
  eventType: string = ''; sourceKind: string = '';
  turn: number = -1; step: number = -1; time: number = 0;
  callId: string = ''; parentCallId: string = ''; rootCallId: string = ''; toolName: string = '';
  phase: string = ''; failed: boolean = false; outcome: string = ''; error: string = '';
  args: string = ''; output: string = ''; status: string = ''; turnKey: string = '';
  children: NativeMessage[] = []; foldable: boolean = false; closed: boolean = true;
  images: NativeImageAttachment[] = [];
  id: string = '';
  seq: number = 0;
  role: string = '';
  label: string = '';
  text: string = '';
  reasoning: string = '';
  blocks: NativeTextBlock[] = [];
  detail: string = '';
}
export class NativeToolUpdate {
  callId: string = ''; name: string = ''; argsDelta: string = ''; arguments: string = ''; replace: boolean = false;
}
export class NativeSession {
  titleKnown: boolean = false;
  origin: string = ''; parentSessionId: string = ''; agentPreset: string = '';
  id: string = '';
  title: string = '';
  blank: boolean | undefined = undefined;
  cwd: string = '';
  running: boolean = false;
  updatedAt: number = 0;
}
export class NativeWorkspaceItem {
  workspaceId: string = ''; path: string = ''; title: string = ''; sessionIds: string[] = [];
}
export class NativeWorkspaceSnapshot {
  available: boolean = false; items: NativeWorkspaceItem[] = [];
  archivedSessionIds: string[] = []; pinnedSessionIds: string[] = [];
}
export class NativeWorkspaceRow {
  key: string = ''; group: boolean = false; title: string = ''; count: number = 0;
  workspaceId: string = ''; session: NativeSession = new NativeSession();
}
export function nativeToolsParent(page: string): string {
  if (page === 'models' || page === 'efforts') return 'modelsRoot';
  if (page === 'queueEdit') return 'queue';
  return '';
}

/** New hosts expose blank explicitly; keep a fallback for older gateway versions. */
export function nativeSessionVisible(session: NativeSession, model: NativeSessionModel | undefined): boolean {
  if (session.running || (model !== undefined && (model.running || model.waiting || model.messages.some((row: NativeMessage) =>
    (row.role === 'user' || row.role === 'assistant') && !!(row.text || row.reasoning || row.images?.length))))) return true;
  if (typeof session.blank === 'boolean') return !session.blank;
  const title = session.title.trim();
  return title.length > 0 && title !== '新会话';
}
export function nativeWorkspaceSessions(sessions: NativeSession[], snapshot: NativeWorkspaceSnapshot, workspaceId: string,
  query: string, models: Map<string, NativeSessionModel>, selectedId: string = '', manual: boolean = false): NativeSession[] {
  const workspace = snapshot.items.find((item: NativeWorkspaceItem) => item.workspaceId === workspaceId);
  const archived: Set<string> = new Set<string>(snapshot.archivedSessionIds);
  const members: Set<string> = new Set<string>(workspace?.sessionIds || []);
  const pinned: Set<string> = new Set<string>(snapshot.pinnedSessionIds);
  const names: Map<string, string> = new Map<string, string>();
  snapshot.items.forEach((item: NativeWorkspaceItem): void => { item.sessionIds.forEach((id: string): void => { names.set(id, item.title); }); });
  const search = query.trim().toLowerCase();
  const rows = sessions.filter((row: NativeSession) => row.origin !== 'subagent' && !archived.has(row.id) && (row.id === selectedId || nativeSessionVisible(row, models.get(row.id))) &&
    (!workspace || members.has(row.id)) && (!search || !row.blank && (row.title + ' ' + row.id + ' ' + (names.get(row.id) || '') + ' ' + (row.cwd || '')).toLowerCase().includes(search)));
  return rows.sort((a: NativeSession, b: NativeSession): number => {
    if (a.blank === true && a.id === selectedId) return -1;
    if (b.blank === true && b.id === selectedId) return 1;
    if (pinned.has(a.id) !== pinned.has(b.id)) return pinned.has(a.id) ? -1 : 1;
    if (manual && workspace) return workspace.sessionIds.indexOf(a.id) - workspace.sessionIds.indexOf(b.id);
    return b.updatedAt - a.updatedAt || a.id.localeCompare(b.id);
  });
}
export function nativeWorkspaceRows(sessions: NativeSession[], snapshot: NativeWorkspaceSnapshot, workspaceId: string,
  query: string, models: Map<string, NativeSessionModel>, activeId: string, collapsed: string[]): NativeWorkspaceRow[] {
  const visible = nativeWorkspaceSessions(sessions, snapshot, workspaceId, query, models, activeId);
  const rows: NativeWorkspaceRow[] = [];
  const seen: Set<string> = new Set<string>();
  const append = (items: NativeSession[], groupId: string): void => {
    items.forEach((session: NativeSession): void => {
      if (seen.has(session.id)) return; seen.add(session.id);
      if (!query && collapsed.includes(groupId)) return;
      const row = new NativeWorkspaceRow(); row.key = 'session:' + session.id; row.session = session;
      rows.push(row);
    });
  };
  if (workspaceId || !snapshot.items.length) { append(visible, ''); return rows; }
  snapshot.items.forEach((workspace: NativeWorkspaceItem): void => {
    const members = new Set<string>(workspace.sessionIds);
    const items = visible.filter((session: NativeSession) => members.has(session.id));
    if (query && !items.length) return;
    const header = new NativeWorkspaceRow(); header.key = 'workspace:' + workspace.workspaceId;
    header.group = true; header.title = workspace.title; header.workspaceId = workspace.workspaceId; header.count = items.length;
    rows.push(header); append(items, workspace.workspaceId);
  });
  const remaining = visible.filter((session: NativeSession) => !seen.has(session.id));
  if (remaining.length) {
    const header = new NativeWorkspaceRow(); header.key = 'workspace:other'; header.group = true;
    header.title = '其他会话'; header.workspaceId = 'other'; header.count = remaining.length;
    rows.push(header); append(remaining, 'other');
  }
  return rows;
}
export class NativeSessionList {
  protocol: number = 0;
  truncated: boolean = false;
  items: NativeSession[] = [];
}
export class NativeOption { label: string = ''; description: string = ''; }
export class NativeIntent { kind: string = ''; approve: string = ''; reject: string = ''; always: string = ''; }
export class NativeQuestion {
  id: string = ''; header: string = ''; question: string = ''; detail: string = '';
  multiSelect: boolean = false; options: NativeOption[] = []; intent: NativeIntent | null = null;
}
export class NativeLocalized { zh: string = ''; en: string = ''; }
export class NativeInteractionRequest {
  toolName: string = ''; reason: string = ''; displayReason: NativeLocalized | null = null;
  questions: NativeQuestion[] = [];
}
export class NativeReplacement { start: number = -1; end: number = -1; }
export class NativePendingQuestion { callId: string = ''; state: string = ''; questions: NativeQuestion[] = []; }
export class NativeFrame {
  code: string = ''; retryable: boolean = true;
  journal: NativeJournalEntry[] = [];
  toolUpdates: NativeToolUpdate[] = [];
  questions: NativePendingQuestion[] = [];
  callId: string = '';
  remainingMs: number = -1;
  connectionId: string = '';
  eventId: string = '';
  interaction: string = '';
  request: NativeInteractionRequest = new NativeInteractionRequest();
  replacements: NativeReplacement[] = [];
  type: string = '';
  messages: NativeMessage[] = [];
  message: NativeMessage | null = null;
  seq: number = -1;
  cursor: number = -1;
  beforeSeq: number = 0;
  hasMore: boolean = false;
  attemptId: string = '';
  nextIndex: number = 0;
  index: number = 0;
  text: string = '';
  reasoning: string = '';
  replaceStart: number = -1;
  replaceEnd: number = -1;
  running: boolean = false;
  waiting: boolean = false;
}
export class NativeJournalEntry { seq: number = 0; raw: string = ''; }

/** One in-memory session projection. No transcripts or drafts are written to disk. */
export class NativeSessionModel {
  readonly journal: Map<number, string> = new Map<number, string>();
  readonly disclosures: Map<string, boolean> = new Map<string, boolean>();
  readonly turnDisclosure: Map<string, boolean> = new Map<string, boolean>();
  collapseThrough: number = -1;
  lastSeq(): number { return this.cursor; }
  readonly expandedTurns: Set<string> = new Set<string>();
  streamTools: NativeMessage[] = [];
  messages: NativeMessage[] = [];
  historyCut: number = -1;
  historyBefore: number = -1;
  hasMore: boolean = false;
  running: boolean = false;
  waiting: boolean = false;
  streamText: string = '';
  streamReasoning: string = '';
  private attemptId: string = '';
  private nextIndex: number = 0;
  private cursor: number = -1;
  private replacements: NativeReplacement[] = [];

  private remember(ranges: NativeReplacement[]): void {
    ranges.forEach((range: NativeReplacement) => {
      if (!this.replacements.some((existing: NativeReplacement) => existing.start === range.start && existing.end === range.end)) this.replacements.push(range);
      this.journal.forEach((_value: string, seq: number): void => { if (seq >= range.start && seq <= range.end) this.journal.delete(seq); });
    });
  }
  private visible(item: NativeMessage): boolean {
    if (item.role === 'detail') return false;
    if (item.role === 'user') {
      if (item.sourceKind && !['user', 'steer', 'client'].includes(item.sourceKind)) return false;
      if (!item.sourceKind && /^(?:current runtime context\.|time sampled while preparing turn|browser time zone for this request:|elapsed since the preceding model-visible message:|current working directory:|current dsh file policy:|<system[-_]reminder>)/i.test((item.text || '').trimStart())) return false;
    }
    return !this.replacements.some((range: NativeReplacement) => item.seq >= range.start && item.seq <= range.end);
  }
  private updateTools(updates: NativeToolUpdate[]): void {
    for (const update of updates || []) {
      let tool = this.streamTools.find((item: NativeMessage) => item.callId === update.callId);
      if (!tool) {
        if (!update.name) continue;
        tool = new NativeMessage(); tool.id = 'preparing-' + update.callId; tool.role = 'tool';
        tool.callId = update.callId; tool.toolName = update.name; tool.phase = 'preparing'; tool.time = Date.now();
        this.streamTools.push(tool);
      }
      if (update.name) tool.toolName = update.name;
      tool.text = update.replace ? update.arguments : tool.text + update.argsDelta;
    }
  }

  apply(frame: NativeFrame): void {
    (frame.journal || []).forEach((entry: NativeJournalEntry): void => { this.journal.set(entry.seq, entry.raw); });
    if (frame.type === 'snapshot') {
      // Retain loaded history on foreground/reconnect, applying replacement ranges.
      this.remember(frame.replacements || []);
      const boundary = frame.beforeSeq === undefined ? 0 : frame.beforeSeq;
      const older = this.messages.filter((item: NativeMessage) => item.seq < boundary &&
        this.visible(item));
      this.messages = older.concat(frame.messages || []).filter((item: NativeMessage) => this.visible(item));
      if (older.length === 0) { this.hasMore = frame.hasMore === true; this.historyBefore = boundary; }
      this.historyCut = frame.cursor;
      this.cursor = frame.cursor;
      this.attemptId = frame.attemptId || '';
      this.nextIndex = frame.nextIndex || 0;
      this.streamText = frame.text || '';
      this.streamReasoning = frame.reasoning || '';
      this.streamTools = []; this.updateTools(frame.toolUpdates);
    } else if (frame.type === 'state') {
      this.running = frame.running;
      this.waiting = frame.waiting;
    } else if (frame.type === 'event') {
      if (!Number.isSafeInteger(frame.seq) || frame.seq <= this.cursor) return;
      this.cursor = frame.seq;
      if (frame.replaceStart >= 0 && frame.replaceEnd >= frame.replaceStart) {
        const range = new NativeReplacement(); range.start = frame.replaceStart; range.end = frame.replaceEnd;
        this.remember([range]);
        this.messages = this.messages.filter((item: NativeMessage) => this.visible(item));
      }
      if (frame.message && this.visible(frame.message)) {
        this.messages = this.messages.concat([frame.message]);
      }
    } else if (frame.type === 'start') {
      this.attemptId = frame.attemptId;
      this.nextIndex = 0;
      this.streamText = ''; this.streamReasoning = '';
      this.streamTools = [];
    } else if (frame.type === 'delta') {
      if (frame.attemptId !== this.attemptId) throw new Error('Stream attempt changed');
      if (frame.index < this.nextIndex) return;
      if (frame.index !== this.nextIndex) throw new Error('Stream gap');
      this.nextIndex++;
      this.streamText = this.streamText + (frame.text || '');
      this.streamReasoning = this.streamReasoning + (frame.reasoning || '');
      this.updateTools(frame.toolUpdates);
    } else if (frame.type === 'end' && frame.attemptId === this.attemptId) {
      this.attemptId = ''; this.streamText = ''; this.streamReasoning = '';
      this.streamTools = [];
    } else if (frame.type === 'error') throw new Error('Native stream unavailable');
  }

  prepend(page: NativeFrame): void {
    this.remember(page.replacements || []);
    (page.journal || []).forEach((entry: NativeJournalEntry): void => {
      if (!this.replacements.some((range: NativeReplacement) => entry.seq >= range.start && entry.seq <= range.end) && !this.journal.has(entry.seq)) this.journal.set(entry.seq, entry.raw);
    });
    const existing: Set<number> = new Set<number>(this.messages.map((item: NativeMessage) => item.seq));
    this.messages = page.messages.filter((item: NativeMessage) => !existing.has(item.seq)).concat(this.messages).filter((item: NativeMessage) => this.visible(item));
    this.hasMore = page.hasMore;
    this.historyBefore = page.beforeSeq;
  }
}
