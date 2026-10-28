export class NativeTextBlock {
  kind: string = 'text';
  text: string = '';
  language: string = '';
}
export class NativeMessage {
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
  running: boolean = false;
  updatedAt: number = 0;
}
export class NativeSessionList {
  protocol: number = 0;
  truncated: boolean = false;
  items: NativeSession[] = [];
}
export class NativeReplacement { start: number = -1; end: number = -1; }
export class NativeFrame {
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

  apply(frame: NativeFrame): void {
    if (frame.type === 'snapshot') {
      // Retain loaded history on foreground/reconnect, applying replacement ranges.
      const boundary = frame.beforeSeq === undefined ? 0 : frame.beforeSeq;
      const older = this.messages.filter((item: NativeMessage) => item.seq < boundary &&
        !(frame.replacements || []).some((range: NativeReplacement) => item.seq >= range.start && item.seq <= range.end));
      this.messages = older.concat(frame.messages || []);
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
        this.messages = this.messages.filter((item: NativeMessage) => item.seq < frame.replaceStart || item.seq > frame.replaceEnd);
      }
      if (frame.message) {
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
    const existing: Set<number> = new Set<number>(this.messages.map((item: NativeMessage) => item.seq));
    this.messages = page.messages.filter((item: NativeMessage) => !existing.has(item.seq)).concat(this.messages);
    this.hasMore = page.hasMore;
    this.historyBefore = page.beforeSeq;
  }
}
