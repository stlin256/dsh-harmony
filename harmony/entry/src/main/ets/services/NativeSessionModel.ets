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
export class NativeFrame {
  type: string = '';
  messages: NativeMessage[] = [];
  message: NativeMessage | null = null;
  seq: number = -1;
  cursor: number = -1;
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
      this.messages = (frame.messages || []).slice(-400);
      this.hasMore = frame.hasMore === true;
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
        if (this.messages.length >= 400) this.hasMore = true;
        this.messages = this.messages.concat([frame.message]).slice(-400);
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
      this.streamText = (this.streamText + (frame.text || '')).slice(0, 24000);
      this.streamReasoning = (this.streamReasoning + (frame.reasoning || '')).slice(0, 24000);
    } else if (frame.type === 'end' && frame.attemptId === this.attemptId) {
      this.attemptId = ''; this.streamText = ''; this.streamReasoning = '';
    } else if (frame.type === 'error') throw new Error('Native stream unavailable');
  }

  prepend(page: NativeFrame): void {
    const existing: number[] = this.messages.map((item: NativeMessage) => item.seq);
    this.messages = page.messages.filter((item: NativeMessage) => !existing.includes(item.seq)).concat(this.messages).slice(-1000);
    this.hasMore = page.hasMore;
  }
}
