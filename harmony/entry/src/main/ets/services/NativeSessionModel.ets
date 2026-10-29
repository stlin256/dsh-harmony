export class NativeTextBlock {
  kind: string = 'text';
  text: string = '';
  language: string = '';
}
export class NativeImageAttachment {
  attachmentId: string = ''; mediaType: string = ''; bytes: number = 0;
  width: number = 0; height: number = 0; name: string = '';
}
export class NativeMessage {
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
export class NativeSession {
  id: string = '';
  title: string = '';
  blank: boolean | undefined = undefined;
  running: boolean = false;
  updatedAt: number = 0;
}

/** New hosts expose blank explicitly; keep a fallback for older gateway versions. */
export function nativeSessionVisible(session: NativeSession, model: NativeSessionModel | undefined): boolean {
  if (session.running || (model !== undefined && (model.running || model.waiting || model.messages.length > 0))) return true;
  if (typeof session.blank === 'boolean') return !session.blank;
  const title = session.title.trim();
  return title.length > 0 && title !== '新会话';
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

/** One in-memory session projection. No transcripts or drafts are written to disk. */
export class NativeSessionModel {
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
    });
  }
  private visible(item: NativeMessage): boolean {
    if (item.role === 'detail') return false;
    return !this.replacements.some((range: NativeReplacement) => item.seq >= range.start && item.seq <= range.end);
  }

  apply(frame: NativeFrame): void {
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
    } else if (frame.type === 'delta') {
      if (frame.attemptId !== this.attemptId) throw new Error('Stream attempt changed');
      if (frame.index < this.nextIndex) return;
      if (frame.index !== this.nextIndex) throw new Error('Stream gap');
      this.nextIndex++;
      this.streamText = this.streamText + (frame.text || '');
      this.streamReasoning = this.streamReasoning + (frame.reasoning || '');
    } else if (frame.type === 'end' && frame.attemptId === this.attemptId) {
      this.attemptId = ''; this.streamText = ''; this.streamReasoning = '';
    } else if (frame.type === 'error') throw new Error('Native stream unavailable');
  }

  prepend(page: NativeFrame): void {
    this.remember(page.replacements || []);
    const existing: Set<number> = new Set<number>(this.messages.map((item: NativeMessage) => item.seq));
    this.messages = page.messages.filter((item: NativeMessage) => !existing.has(item.seq)).concat(this.messages).filter((item: NativeMessage) => this.visible(item));
    this.hasMore = page.hasMore;
    this.historyBefore = page.beforeSeq;
  }
}
