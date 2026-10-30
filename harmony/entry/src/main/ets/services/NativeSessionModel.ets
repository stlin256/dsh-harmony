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
  footerCopyText: string = '';
  footerCopyMessageId: string = '';
  footerOutcome: string = '';
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
  workspaceId: string = ''; workspaceTitle: string = ''; section: string = '';
  pinned: boolean = false; session: NativeSession = new NativeSession();
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
  query: string, models: Map<string, NativeSessionModel>, selectedId: string = '',
  recentInteractions: Map<string, number> = new Map<string, number>()): NativeSession[] {
  const workspace = snapshot.items.find((item: NativeWorkspaceItem) => item.workspaceId === workspaceId);
  const archived: Set<string> = new Set<string>(snapshot.archivedSessionIds);
  const members: Set<string> = new Set<string>(workspace?.sessionIds || []);
  const pinned: Set<string> = new Set<string>(snapshot.pinnedSessionIds);
  const names: Map<string, string> = new Map<string, string>();
  snapshot.items.forEach((item: NativeWorkspaceItem): void => { item.sessionIds.forEach((id: string): void => { names.set(id, item.title); }); });
  const search = query.trim().toLowerCase();
  const rows = sessions.filter((row: NativeSession): boolean => row.origin !== 'subagent' &&
    !archived.has(row.id) && !pinned.has(row.id) &&
    (row.id === selectedId || nativeSessionVisible(row, models.get(row.id))) &&
    (!workspace || members.has(row.id)) && (!search || !row.blank && (row.title + ' ' + row.id + ' ' + (names.get(row.id) || '') + ' ' + (row.cwd || '')).toLowerCase().includes(search)));
  return rows.sort((a: NativeSession, b: NativeSession): number => {
    if (a.blank === true && a.id === selectedId) return -1;
    if (b.blank === true && b.id === selectedId) return 1;
    const aTime = Math.max(a.updatedAt, recentInteractions.get(a.id) || 0);
    const bTime = Math.max(b.updatedAt, recentInteractions.get(b.id) || 0);
    return bTime - aTime || a.id.localeCompare(b.id);
  });
}

/** Reorder workspace ids without touching any workspace membership. */
export function nativeWorkspaceDragOrder(order: string[], sourceId: string, targetId: string,
  after: boolean): string[] | null {
  if (!sourceId || !targetId || sourceId === targetId) return null;
  if (!order.includes(sourceId) || !order.includes(targetId)) return null;
  const next = order.filter((id: string): boolean => id !== sourceId);
  const targetIndex = next.indexOf(targetId);
  if (targetIndex < 0) return null;
  next.splice(targetIndex + (after ? 1 : 0), 0, sourceId);
  return next;
}

export function nativeBackToBottomAvailable(atEnd: boolean, userHasScrolled: boolean,
  returningToBottom: boolean): boolean {
  return !atEnd && userHasScrolled && !returningToBottom;
}

export function nativeBackToBottomHasNewContent(followTail: boolean, eventType: string): boolean {
  return !followTail &&
    (eventType === 'event' || eventType === 'delta' || eventType === 'snapshot');
}

export function nativeWorkspaceRows(sessions: NativeSession[], snapshot: NativeWorkspaceSnapshot, workspaceId: string,
  query: string, models: Map<string, NativeSessionModel>, activeId: string, collapsed: string[],
  recentInteractions: Map<string, number> = new Map<string, number>()): NativeWorkspaceRow[] {
  const workspaceBySession: Map<string, NativeWorkspaceItem> = new Map<string, NativeWorkspaceItem>();
  snapshot.items.forEach((workspace: NativeWorkspaceItem): void => {
    workspace.sessionIds.forEach((id: string): void => {
      if (!workspaceBySession.has(id)) workspaceBySession.set(id, workspace);
    });
  });
  const archived: Set<string> = new Set<string>(snapshot.archivedSessionIds);
  const pinned: Set<string> = new Set<string>(snapshot.pinnedSessionIds);
  const search = query.trim().toLowerCase();
  const visible = sessions.filter((session: NativeSession): boolean =>
    session.origin !== 'subagent' && !archived.has(session.id) &&
    (session.id === activeId || nativeSessionVisible(session, models.get(session.id))) &&
    (!search || !session.blank && (session.title + ' ' + session.id + ' ' +
      (workspaceBySession.get(session.id)?.title || '') + ' ' +
      (session.cwd || '')).toLowerCase().includes(search)));
  const byRecency = (a: NativeSession, b: NativeSession): number => {
    const aTime = Math.max(a.updatedAt, recentInteractions.get(a.id) || 0);
    const bTime = Math.max(b.updatedAt, recentInteractions.get(b.id) || 0);
    return bTime - aTime || a.id.localeCompare(b.id);
  };
  const rows: NativeWorkspaceRow[] = [];
  const seen: Set<string> = new Set<string>();
  const append = (items: NativeSession[], groupId: string): void => {
    items.forEach((session: NativeSession): void => {
      if (seen.has(session.id)) return; seen.add(session.id);
      if (!query && collapsed.includes(groupId)) return;
      const row = new NativeWorkspaceRow(); row.key = 'session:' + session.id; row.session = session;
      row.workspaceId = groupId;
      row.section = groupId === 'pinned' ? 'pinnedSession' :
        groupId === 'other' ? 'otherSession' : 'workspaceSession';
      row.pinned = pinned.has(session.id);
      row.workspaceTitle = workspaceBySession.get(session.id)?.title || '';
      rows.push(row);
    });
  };
  const scoped = visible.filter((session: NativeSession): boolean => {
    if (!workspaceId) return true;
    return workspaceBySession.get(session.id)?.workspaceId === workspaceId;
  });
  const pinnedItems = scoped.filter((session: NativeSession): boolean =>
    session.blank !== true && pinned.has(session.id)).sort(byRecency);
  if (pinnedItems.length) {
    const header = new NativeWorkspaceRow();
    header.key = 'section:pinned'; header.group = true; header.title = '置顶';
    header.workspaceId = 'pinned'; header.section = 'pinnedHeader';
    header.count = pinnedItems.length;
    rows.push(header);
    append(pinnedItems, 'pinned');
  }
  const ordinary = scoped.filter((session: NativeSession): boolean =>
    session.blank === true || !pinned.has(session.id));
  if (workspaceId || !snapshot.items.length) {
    append(ordinary.sort((a: NativeSession, b: NativeSession): number => {
      if (a.blank === true && a.id === activeId) return -1;
      if (b.blank === true && b.id === activeId) return 1;
      return byRecency(a, b);
    }), workspaceId);
    return rows;
  }
  snapshot.items.forEach((workspace: NativeWorkspaceItem): void => {
    const members = new Set<string>(workspace.sessionIds);
    const items = ordinary.filter((session: NativeSession): boolean =>
      members.has(session.id)).sort((a: NativeSession, b: NativeSession): number => {
      if (a.blank === true && a.id === activeId) return -1;
      if (b.blank === true && b.id === activeId) return 1;
      return byRecency(a, b);
    });
    if (query && !items.length) return;
    const header = new NativeWorkspaceRow(); header.key = 'workspace:' + workspace.workspaceId;
    header.group = true; header.title = workspace.title; header.workspaceId = workspace.workspaceId; header.count = items.length;
    header.section = 'workspaceHeader'; header.workspaceTitle = workspace.title;
    rows.push(header); append(items, workspace.workspaceId);
  });
  const remaining = ordinary.filter((session: NativeSession): boolean =>
    !seen.has(session.id)).sort(byRecency);
  if (remaining.length) {
    const header = new NativeWorkspaceRow(); header.key = 'workspace:other'; header.group = true;
    header.title = '其他会话'; header.workspaceId = 'other'; header.count = remaining.length;
    header.section = 'otherHeader';
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
export class NativeCacheFlag {
  key: string = '';
  value: boolean = false;
}

export class NativeSessionCacheRecord {
  version: number = 1;
  journal: NativeJournalEntry[] = [];
  expandedTurns: string[] = [];
  disclosures: NativeCacheFlag[] = [];
  turnDisclosure: NativeCacheFlag[] = [];
  streamTools: NativeMessage[] = [];
  messages: NativeMessage[] = [];
  replacements: NativeReplacement[] = [];
  historyCut: number = -1;
  historyBefore: number = -1;
  hasMore: boolean = false;
  running: boolean = false;
  waiting: boolean = false;
  streamText: string = '';
  streamReasoning: string = '';
  attemptId: string = '';
  nextIndex: number = 0;
  cursor: number = -1;
  collapseThrough: number = -1;
}

/** One session projection. The workspace persists its record in encrypted RDB. */
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

  capture(): NativeSessionCacheRecord {
    const value = new NativeSessionCacheRecord();
    this.journal.forEach((raw: string, seq: number): void => {
      const entry = new NativeJournalEntry();
      entry.seq = seq;
      entry.raw = raw;
      value.journal.push(entry);
    });
    value.expandedTurns = Array.from(this.expandedTurns);
    this.disclosures.forEach((open: boolean, key: string): void => {
      const flag = new NativeCacheFlag();
      flag.key = key;
      flag.value = open;
      value.disclosures.push(flag);
    });
    this.turnDisclosure.forEach((open: boolean, key: string): void => {
      const flag = new NativeCacheFlag();
      flag.key = key;
      flag.value = open;
      value.turnDisclosure.push(flag);
    });
    value.streamTools = this.streamTools;
    value.messages = this.messages;
    value.replacements = this.replacements;
    value.historyCut = this.historyCut;
    value.historyBefore = this.historyBefore;
    value.hasMore = this.hasMore;
    value.running = this.running;
    value.waiting = this.waiting;
    value.streamText = this.streamText;
    value.streamReasoning = this.streamReasoning;
    value.attemptId = this.attemptId;
    value.nextIndex = this.nextIndex;
    value.cursor = this.cursor;
    value.collapseThrough = this.collapseThrough;
    return value;
  }

  restore(value: NativeSessionCacheRecord): void {
    if (value.version !== 1 || !Array.isArray(value.messages)) {
      throw new Error('Unsupported transcript cache');
    }
    this.journal.clear();
    (value.journal || []).forEach((entry: NativeJournalEntry): void => {
      if (Number.isSafeInteger(entry.seq) && typeof entry.raw === 'string') {
        this.journal.set(entry.seq, entry.raw);
      }
    });
    this.expandedTurns.clear();
    (value.expandedTurns || []).forEach((turn: string): void => {
      if (turn) this.expandedTurns.add(turn);
    });
    this.disclosures.clear();
    (value.disclosures || []).forEach((flag: NativeCacheFlag): void => {
      if (flag && typeof flag.key === 'string' && flag.key) this.disclosures.set(flag.key, flag.value === true);
    });
    this.turnDisclosure.clear();
    (value.turnDisclosure || []).forEach((flag: NativeCacheFlag): void => {
      if (flag && typeof flag.key === 'string' && flag.key) this.turnDisclosure.set(flag.key, flag.value === true);
    });
    this.streamTools = Array.isArray(value.streamTools) ? value.streamTools : [];
    this.messages = value.messages;
    this.replacements = Array.isArray(value.replacements) ? value.replacements : [];
    this.historyCut = Number.isFinite(value.historyCut) ? value.historyCut : -1;
    this.historyBefore = Number.isFinite(value.historyBefore) ? value.historyBefore : -1;
    this.hasMore = value.hasMore === true;
    this.running = value.running === true;
    this.waiting = value.waiting === true;
    this.streamText = typeof value.streamText === 'string' ? value.streamText : '';
    this.streamReasoning = typeof value.streamReasoning === 'string' ? value.streamReasoning : '';
    this.attemptId = typeof value.attemptId === 'string' ? value.attemptId : '';
    this.nextIndex = Number.isSafeInteger(value.nextIndex) ? value.nextIndex : 0;
    this.cursor = Number.isSafeInteger(value.cursor) ? value.cursor : -1;
    this.collapseThrough = Number.isSafeInteger(value.collapseThrough) ? value.collapseThrough : -1;
  }

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
