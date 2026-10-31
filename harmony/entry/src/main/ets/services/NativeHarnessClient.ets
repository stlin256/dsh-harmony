import { http, webSocket } from '@kit.NetworkKit';
import { webview } from '@kit.ArkWeb';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { NativeFrame, NativeSession, NativeSessionList, NativeSessionModel, NativeWorkspaceSnapshot } from './NativeSessionModel';
import { NativeHostSettings } from './NativeHostSettings';
import { NativeModelDirectory } from './NativeModelDirectory';
import { nativeFileWindowMetadata } from './NativeFileWindow';

export class NativeHttpError extends Error {
  status: number;
  code: string;
  constructor(status: number, code: string = '') { super(status === 401 ? '请先登录工作空间' : '操作未确认，请刷新'); this.status = status; this.code = code; }
}
export class GatewayState {
  mode: string = '';
  authOrigin: string = '';
  authenticated: boolean = false;
  pushConfigured: boolean = false;
}
export class NativeImageDraft { id: string = ''; name: string = ''; mediaType: string = ''; data: string = ''; }
export class NativeAttachmentDraft {
  id: string = ''; kind: string = ''; name: string = ''; mediaType: string = '';
  uri: string = ''; status: string = 'uploading'; receiptId: string = ''; error: string = '';
  retryable: boolean = true; bytes: number = 0; data: Uint8Array = new Uint8Array();
}
export class NativeUploadResult { receiptId: string = ''; }
export class NativePromptAttachment { type: string = 'file'; receiptId: string = ''; }
export class NativeCreatedSession { id: string = ''; }
export class NativeFilePage {
  absolutePath: string = ''; version: string = ''; text: string = '';
  lines: number = 0; offset: number = 1; eof: boolean = false;
}
export class NativeFileStat {
  absolutePath: string = ''; version: string = ''; bytes: number = -1;
}
export class NativeDirectoryEntry {
  name: string = ''; type: string = 'other'; size: number = -1;
}
export class NativeDirectoryListing {
  path: string = ''; entries: NativeDirectoryEntry[] = []; truncated: boolean = false;
}
export class NativeFileBytes {
  protocol: number = 0;
  absolutePath: string = ''; version: string = ''; bytes: number = -1;
  offset: number = 0; eof: boolean = false; length: number = 0; data: Uint8Array = new Uint8Array();
}
class NativeFileBytesRequest {
  sessionId: string;
  path: string;
  offset: number;
  length: number;
  baseFile?: string;
  constructor(sessionId: string, path: string, offset: number, length: number) {
    this.sessionId = sessionId;
    this.path = path;
    this.offset = offset;
    this.length = length;
  }
}
class NativeDirectorySearch {
  path: string;
  depth: number;
  constructor(path: string, depth: number) {
    this.path = path;
    this.depth = depth;
  }
}

export class NativeHarnessClient {
  readonly modelDirectory: NativeModelDirectory = new NativeModelDirectory((value: string): Promise<string> => this.operation(value), (): void => {
    AppStorage.setOrCreate<number>('nativeModelRevision', (AppStorage.get<number>('nativeModelRevision') || 0) + 1);
  });
  readonly hostSettings: NativeHostSettings = new NativeHostSettings((value: string): Promise<string> => this.operation(value), (): void => {
    AppStorage.setOrCreate<number>('nativeHostSettingsRevision', (AppStorage.get<number>('nativeHostSettingsRevision') || 0) + 1);
  });
  private origin: string;
  private cacheIdentity: string = '';
  private socket: webSocket.WebSocket | null = null;
  private generation: number = 0;
  private stateRead: Promise<GatewayState> | null = null;
  private sessionRead: Promise<NativeSessionList> | null = null;
  private workspaceRead: Promise<NativeWorkspaceSnapshot> | null = null;
  private pageReads: Map<string, Promise<NativeFrame>> = new Map<string, Promise<NativeFrame>>();
  private sessionCwds: Map<string, string> = new Map<string, string>();
  private browsePaths: Map<string, string> = new Map<string, string>();
  private fileLookups: Map<string, Promise<string>> = new Map<string, Promise<string>>();
  readonly images: Map<string, NativeImageDraft[]> = new Map<string, NativeImageDraft[]>();
  readonly attachments: Map<string, NativeAttachmentDraft[]> = new Map<string, NativeAttachmentDraft[]>();
  readonly drafts: Map<string, string> = new Map<string, string>();
  readonly uncertain: Set<string> = new Set<string>();
  /** In-memory only: retain visible chat history across session switches and settings. */
  readonly models: Map<string, NativeSessionModel> = new Map<string, NativeSessionModel>();
  selectedId: string = '';

  constructor(origin: string) { this.origin = origin; }
  cacheKey(): string { return this.origin + '#' + (this.cacheIdentity || 'pending'); }
  /** Isolate navigation snapshots by the persisted gateway session without exposing it. */
  async prepareCacheKey(): Promise<void> {
    const value = await this.cookie();
    let hash = 2166136261;
    for (let index = 0; index < value.length; index++) {
      hash ^= value.charCodeAt(index);
      hash = Math.imul(hash, 16777619);
    }
    this.cacheIdentity = value ? (hash >>> 0).toString(16) : 'anonymous';
  }

  private async cookie(): Promise<string> {
    try {
      const cookies = await webview.WebCookieManager.fetchCookie(this.origin + '/');
      // Send only the selected origin's gateway session cookies; never follow redirects.
      return cookies.split(';').map((item: string) => item.trim())
        .filter((item: string) => /^(?:pocket|__Host-hpg_session|dsh-auth-[A-Za-z0-9_-]+)=[A-Za-z0-9_.-]+$/.test(item)).join('; ');
    } catch (_) { return ''; }
  }

  async request(path: string, method: http.RequestMethod = http.RequestMethod.GET, body: string = ''): Promise<string> {
    // Fixed root-owned endpoints only; no credentials in URLs or redirect hops.
    if (!/^\/pocket\/api\/(?:state|overview|logout|device|auth\/(?:none|native)|native\/(?:sessions|workspaces|create|page|upload|file(?:\/(?:stat|list|bytes))?|prompt|cancel|operation|answer))$/.test(path)) throw new Error('Unsupported endpoint');
    const task = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: method, header: { 'Content-Type': 'application/json', Origin: this.origin, Cookie: await this.cookie() },
        expectDataType: http.HttpDataType.STRING, usingCache: false,
        maxRedirects: 0, connectTimeout: 10000, readTimeout: 25000
      };
      if (body.length > 0) options.extraData = body;
      if (path.startsWith('/pocket/api/native/')) {
        // Streaming Network Kit API avoids HttpResponse's fixed receive-buffer ceiling.
        const chunks: Uint8Array[] = [];
        let bytes: number = 0;
        const end = new Promise<void>((resolve: () => void) => { task.on('dataEnd', resolve); });
        task.on('dataReceive', (data: ArrayBuffer): void => {
          const part = new Uint8Array(data); chunks.push(part); bytes += part.byteLength;
        });
        const status = await task.requestInStream(this.origin + path, options);
        await end;
        const buffer = new Uint8Array(bytes);
        let offset: number = 0;
        chunks.forEach((part: Uint8Array) => { buffer.set(part, offset); offset += part.byteLength; });
        const text = util.TextDecoder.create('utf-8').decodeToString(buffer);
        if (status < 200 || status >= 300) {
          let code = '';
          try { const value = JSON.parse(text) as Record<string, Object>; if (typeof value.code === 'string') code = value.code; } catch (_) {}
          throw new NativeHttpError(status, code);
        }
        return text;
      }
      const response = await task.request(this.origin + path, options);
      if (response.responseCode < 200 || response.responseCode >= 300) throw new NativeHttpError(response.responseCode);
      // Share only this gateway's device-management session with ArkWeb. The
      // upstream Harness credential never reaches the native app.
      const headers = response.header as Record<string, Object>;
      const value = headers['set-cookie'] || headers['Set-Cookie'];
      const cookies: string[] = typeof value === 'string' ? [value] : Array.isArray(value) ? value as string[] : [];
      for (const cookie of cookies) {
        if ((path === '/pocket/api/auth/none' && /^pocket=/.test(cookie)) ||
          (path === '/pocket/api/auth/native' && /^dsh-auth-[A-Za-z0-9_-]+=/.test(cookie))) {
          await webview.WebCookieManager.configCookie(this.origin + '/', cookie, false, true);
          await webview.WebCookieManager.saveCookieAsync();
        }
      }
      return response.result as string;
    } finally { task.destroy(); }
  }

  async state(): Promise<GatewayState> {
    if (this.stateRead) return this.stateRead;
    const pending = this.request('/pocket/api/state')
      .then((value: string): GatewayState => JSON.parse(value) as GatewayState)
      .finally((): void => { this.stateRead = null; });
    this.stateRead = pending;
    return pending;
  }
  async loginNative(token: string): Promise<void> {
    await this.request('/pocket/api/auth/native', http.RequestMethod.POST, JSON.stringify({ token: token }));
  }
  async sessions(): Promise<NativeSessionList> {
    if (this.sessionRead) return this.sessionRead;
    const pending = this.request('/pocket/api/native/sessions')
      .then((value: string): NativeSessionList => {
        const parsed = JSON.parse(value) as NativeSessionList;
        this.sessionCwds.clear();
        parsed.items.forEach((session: NativeSession): void => {
          if (session.cwd) this.sessionCwds.set(session.id, session.cwd);
        });
        return parsed;
      })
      .finally((): void => { this.sessionRead = null; });
    this.sessionRead = pending;
    return pending;
  }
  sessionCwd(id: string): string { return this.sessionCwds.get(id) || ''; }
  workspaceRelativePath(sessionId: string, value: string, workspaceRoot: string = ''): string {
    const normalize = (input: string): string => {
      const clean = input.replace(/\\/g, '/').replace(/^\/+/, '').replace(/^\.\/+/, '')
        .replace(/\/+/g, '/').replace(/\/+$/, '');
      if (!clean || clean === '.') return '';
      const parts: string[] = [];
      clean.split('/').forEach((part: string): void => {
        if (!part || part === '.') return;
        if (part === '..') {
          if (parts.length) parts.pop();
          return;
        }
        parts.push(part);
      });
      return parts.join('/');
    };
    let path = normalize(value);
    const cwd = normalize(workspaceRoot || this.sessionCwd(sessionId));
    if (cwd && path === cwd) return '';
    if (cwd && path.startsWith(cwd + '/')) path = path.slice(cwd.length + 1);
    return normalize(path);
  }
  rememberBrowsePath(sessionId: string, path: string): void {
    if (sessionId) this.browsePaths.set(sessionId, this.workspaceRelativePath(sessionId, path));
  }
  lastBrowsePath(sessionId: string): string { return this.browsePaths.get(sessionId) || ''; }
  async workspaces(): Promise<NativeWorkspaceSnapshot> {
    if (this.workspaceRead) return this.workspaceRead;
    const pending = this.request('/pocket/api/native/workspaces')
      .then((value: string): NativeWorkspaceSnapshot => JSON.parse(value) as NativeWorkspaceSnapshot)
      .finally((): void => { this.workspaceRead = null; });
    this.workspaceRead = pending;
    return pending;
  }
  async create(cwd: string = '', agentPreset: string = '', workspaceId: string = '', reuseId: string = ''): Promise<string> {
    const result = JSON.parse(await this.request('/pocket/api/native/create', http.RequestMethod.POST,
      JSON.stringify({ requestId: reuseId || util.generateRandomUUID(), workspaceId: workspaceId || undefined,
        cwd: workspaceId ? undefined : cwd || undefined, agentPreset: agentPreset || undefined }))) as NativeCreatedSession;
    return result.id;
  }
  async page(id: string, before: number, throughSeq: number = -1): Promise<NativeFrame> {
    const key = id + ':' + before + ':' + throughSeq;
    const existing = this.pageReads.get(key);
    if (existing) return existing;
    const pending = this.request('/pocket/api/native/page', http.RequestMethod.POST,
      JSON.stringify({ sessionId: id, beforeSeq: before, throughSeq: throughSeq }))
      .then((value: string): NativeFrame => JSON.parse(value) as NativeFrame)
      .finally((): void => { this.pageReads.delete(key); });
    this.pageReads.set(key, pending);
    return pending;
  }
  async file(id: string, path: string, offset: number = 1, limit: number = 240): Promise<NativeFilePage> {
    return JSON.parse(await this.request('/pocket/api/native/file', http.RequestMethod.POST,
      JSON.stringify({ sessionId: id, path: path, offset: offset, limit: limit }))) as NativeFilePage;
  }
  async statFile(id: string, path: string): Promise<NativeFileStat> {
    return JSON.parse(await this.request('/pocket/api/native/file/stat', http.RequestMethod.POST,
      JSON.stringify({ sessionId: id, path: path }))) as NativeFileStat;
  }
  async listFiles(id: string, path: string): Promise<NativeDirectoryListing> {
    return JSON.parse(await this.request('/pocket/api/native/file/list', http.RequestMethod.POST,
      JSON.stringify({ sessionId: id, path: path }))) as NativeDirectoryListing;
  }
  /**
   * Resolve a model-emitted basename that was written to a nested directory.
   * Exact paths never reach this method. Directory enumeration remains scoped
   * to the Session and is bounded so a link tap cannot walk an entire project.
   */
  async findWorkspaceFile(id: string, name: string): Promise<string> {
    if (!id || !name) return '';
    const key = id + '\n' + name;
    const pending = this.fileLookups.get(key);
    if (pending) return pending;
    const lookup = this.searchWorkspaceFile(id, name)
      .finally((): void => { this.fileLookups.delete(key); });
    this.fileLookups.set(key, lookup);
    return lookup;
  }
  private async searchWorkspaceFile(id: string, name: string): Promise<string> {
    const pending: NativeDirectorySearch[] = [new NativeDirectorySearch('', 0)];
    const visited: Set<string> = new Set<string>();
    while (pending.length > 0 && visited.size < 64) {
      const directory = pending.shift() as NativeDirectorySearch;
      if (visited.has(directory.path)) continue;
      visited.add(directory.path);
      let listing: NativeDirectoryListing;
      try {
        listing = await this.listFiles(id, directory.path || '.');
      } catch (_) {
        continue;
      }
      const match = listing.entries.find((entry: NativeDirectoryEntry): boolean =>
        entry.type === 'file' && entry.name === name);
      if (match) return this.childPath(directory.path, match.name);
      if (directory.depth >= 4) continue;
      listing.entries.forEach((entry: NativeDirectoryEntry): void => {
        if (entry.type === 'directory') {
          pending.push(new NativeDirectorySearch(this.childPath(directory.path, entry.name), directory.depth + 1));
        }
      });
    }
    return '';
  }
  private childPath(parent: string, name: string): string {
    if (!parent) return name;
    return parent.replace(/\/+$/, '') + '/' + name;
  }
  async readFileBytes(id: string, path: string, baseFile: string = '',
    offset: number = 0, length: number = 262144,
    expectedVersion: string = '', expectedBytes: number = -1): Promise<NativeFileBytes> {
    const task = http.createHttp();
    try {
      let header = '';
      task.on('headersReceive', (headers: Object): void => {
        const values = headers as Record<string, Object>;
        Object.keys(values).forEach((key: string): void => {
          if (key.toLowerCase() !== 'x-dsh-file-window') return;
          const value = values[key];
          if (typeof value === 'string') {
            header = value;
          } else if (Array.isArray(value) && typeof value[0] === 'string') {
            header = value[0] as string;
          }
        });
      });
      const chunks: Uint8Array[] = [];
      let total: number = 0;
      const ended = new Promise<void>((resolve: () => void): void => { task.on('dataEnd', resolve); });
      task.on('dataReceive', (data: ArrayBuffer): void => {
        const part = new Uint8Array(data); chunks.push(part); total += part.byteLength;
      });
      const body = new NativeFileBytesRequest(id, path, offset, length);
      if (baseFile) body.baseFile = baseFile;
      const status = await task.requestInStream(this.origin + '/pocket/api/native/file/bytes', {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json', Origin: this.origin, Cookie: await this.cookie() },
        extraData: JSON.stringify(body),
        usingCache: false, maxRedirects: 0, connectTimeout: 10000, readTimeout: 30000
      });
      await ended;
      if (status < 200 || status >= 300) throw new NativeHttpError(status);
      const bytes = new Uint8Array(total);
      let cursor: number = 0;
      chunks.forEach((part: Uint8Array): void => { bytes.set(part, cursor); cursor += part.byteLength; });
      let metadata: NativeFileBytes;
      if (header) {
        const encoded = header.replace(/-/g, '+').replace(/_/g, '/');
        const padded = encoded + '='.repeat((4 - encoded.length % 4) % 4);
        const decoded = new util.Base64Helper().decodeSync(padded);
        metadata = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(decoded)) as NativeFileBytes;
        if (metadata.protocol !== 1 || typeof metadata.version !== 'string' ||
            metadata.offset !== offset || typeof metadata.eof !== 'boolean') {
          throw new Error('Invalid file window');
        }
      } else {
        const fallback = nativeFileWindowMetadata(expectedVersion, expectedBytes, offset, total, length);
        if (!fallback.version) throw new Error('Missing file window metadata');
        metadata = new NativeFileBytes();
        metadata.protocol = 1;
        metadata.version = fallback.version;
        metadata.bytes = fallback.bytes;
        metadata.offset = fallback.offset;
        metadata.eof = fallback.eof;
        metadata.length = fallback.length;
      }
      metadata.data = bytes;
      if (typeof metadata.length !== 'number' || metadata.length !== bytes.length) {
        throw new Error('Invalid file window length');
      }
      return metadata;
    } finally { task.destroy(); }
  }
  async uploadAttachment(id: string, name: string, data: Uint8Array, mediaType: string = ''): Promise<NativeUploadResult> {
    if (!/^[A-Za-z0-9_-]{1,160}$/.test(id) || !name || name.length > 512) throw new Error('Invalid upload');
    const query = '?sessionId=' + encodeURIComponent(id) + '&name=' + encodeURIComponent(name) +
      (mediaType ? '&mediaType=' + encodeURIComponent(mediaType) : '');
    const task = http.createHttp();
    try {
      const chunks: Uint8Array[] = [];
      let total: number = 0;
      const ended = new Promise<void>((resolve: () => void): void => { task.on('dataEnd', resolve); });
      task.on('dataReceive', (part: ArrayBuffer): void => {
        const bytes = new Uint8Array(part);
        chunks.push(bytes); total += bytes.byteLength;
      });
      const status = await task.requestInStream(this.origin + '/pocket/api/native/upload' + query, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/octet-stream',
          'Content-Length': data.byteLength.toString(),
          Origin: this.origin,
          Cookie: await this.cookie()
        },
        extraData: data.buffer as ArrayBuffer,
        usingCache: false, maxRedirects: 0, connectTimeout: 10000, readTimeout: 45000
      });
      await ended;
      if (status < 200 || status >= 300) throw new NativeHttpError(status);
      const response = new Uint8Array(total);
      let offset: number = 0;
      chunks.forEach((part: Uint8Array): void => { response.set(part, offset); offset += part.byteLength; });
      const envelope = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(response)) as Record<string, Object>;
      if (envelope.ok !== true) throw new Error('附件上传失败');
      const value = envelope.value as Record<string, Object> | undefined;
      if (!value || typeof value.receiptId !== 'string' || !value.receiptId) throw new Error('附件上传失败');
      const result = new NativeUploadResult();
      result.receiptId = value.receiptId;
      return result;
    } finally { task.destroy(); }
  }

  async prompt(id: string, text: string, mode: string = 'queue', attachments: NativeAttachmentDraft[] = []): Promise<void> {
    this.uncertain.add(id);
    const ready = attachments.filter((item: NativeAttachmentDraft): boolean =>
      item.status === 'ready' && !!item.receiptId).map((item: NativeAttachmentDraft): NativePromptAttachment => {
      const prompt = new NativePromptAttachment();
      prompt.receiptId = item.receiptId;
      return prompt;
    });
    try {
      await this.request('/pocket/api/native/prompt', http.RequestMethod.POST,
        JSON.stringify({ sessionId: id, requestId: util.generateRandomUUID(), text: text, mode: mode, attachments: ready }));
    } catch (error) {
      if (error instanceof NativeHttpError && error.status >= 400 && error.status < 500) this.uncertain.delete(id);
      throw new Error(error instanceof Error ? error.message : String(error));
    }
    this.uncertain.delete(id);
  }
  async answer(body: string): Promise<void> {
    await this.request('/pocket/api/native/answer', http.RequestMethod.POST, body);
  }
  async operation(body: string): Promise<string> {
    return this.request('/pocket/api/native/operation', http.RequestMethod.POST, body);
  }
  async exportSession(id: string, format: string, receive: (part: ArrayBuffer) => void): Promise<void> {
    if (!/^[A-Za-z0-9_-]{1,160}$/.test(id) || !['markdown', 'zip'].includes(format)) throw new Error('Invalid export');
    const task = http.createHttp();
    try {
      let status = 0;
      let consumerError: Error | null = null;
      const ended = new Promise<void>((resolve: () => void) => { task.on('dataEnd', resolve); });
      task.on('headersReceive', (): void => {});
      task.on('dataReceive', (part: ArrayBuffer): void => {
        try { receive(part); } catch (error) { consumerError = error as Error; }
      });
      status = await task.requestInStream(this.origin + '/pocket/api/native/export?sessionId=' + encodeURIComponent(id) + '&format=' + format + '&includeDescendants=true', {
        method: http.RequestMethod.GET, header: { Origin: this.origin, Cookie: await this.cookie() },
        maxRedirects: 0, usingCache: false, connectTimeout: 10000, readTimeout: 120000
      });
      await ended;
      if (status < 200 || status >= 300) throw new NativeHttpError(status);
      if (consumerError) throw consumerError as Error;
    } finally { task.destroy(); }
  }
  async cancel(id: string): Promise<void> {
    await this.request('/pocket/api/native/cancel', http.RequestMethod.POST, JSON.stringify({ sessionId: id }));
  }
  pause(): void {
    this.generation++;
    const old = this.socket; this.socket = null;
    if (old) {
      old.off('message'); old.off('close'); old.off('error'); old.off('open');
      old.close().catch(() => {});
    }
  }
  clearLocalState(): void {
    this.modelDirectory.clear();
    this.models.clear(); this.drafts.clear(); this.images.clear(); this.attachments.clear(); this.uncertain.clear();
    this.pageReads.clear(); this.sessionCwds.clear(); this.browsePaths.clear();
    this.fileLookups.clear(); this.selectedId = '';
  }
  async follow(id: string, receive: (frame: NativeFrame) => void, ended: (reason: string) => void,
    background: boolean = false): Promise<void> {
    if (!/^[A-Za-z0-9_-]{1,160}$/.test(id)) throw new Error('Invalid session');
    this.pause();
    const generation = this.generation;
    const cookie = await this.cookie();
    if (generation !== this.generation) return;
    const socket = webSocket.createWebSocket(); this.socket = socket;
    let finished: boolean = false;
    let opened: boolean = false;
    const openingTimer = setTimeout(() => { finish('open_timeout'); }, background ? 45000 : 20000);
    const finish = (reason: string): void => {
      if (generation !== this.generation || finished) return;
      finished = true; clearTimeout(openingTimer); socket.close().catch(() => {}); ended(reason);
    };
    socket.on('open', (error: BusinessError): void => {
      if (error) { finish('open_error_' + error.code); return; }
      opened = true; clearTimeout(openingTimer);
    });
    socket.on('message', (error: BusinessError, data: string | ArrayBuffer): void => {
      if (error || generation !== this.generation || finished) return;
      if (!opened) { finish('message_before_open'); return; }
      let frame: NativeFrame;
      try {
        const text = typeof data === 'string' ? data : util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(data));
        frame = JSON.parse(text) as NativeFrame;
      } catch (_) { finish('invalid_frame'); return; }
      try { receive(frame); }
      catch (error) {
        const message = (error as Error).message;
        finish(message === 'Stream gap' ? 'assistant_index_gap' : message === 'Stream attempt changed' ? 'assistant_attempt_changed' : 'frame_handler_error');
      }
    });
    socket.on('close', (_error: BusinessError, result: webSocket.CloseResult): void => {
      finish('close_' + (result?.code || 0));
    });
    socket.on('error', (error: BusinessError): void => { finish('socket_error_' + error.code); });
    const socketOrigin = this.origin.replace(/^https:/, 'wss:').replace(/^http:/, 'ws:');
    try {
      const profile = background ? '&profile=background' : '';
      const created = await socket.connect(socketOrigin + '/pocket/native/live?sessionId=' +
        encodeURIComponent(id) + profile,
        { header: { cookie: cookie }, supportOriginPort: true });
      if (!created) finish('connect_rejected');
    } catch (_) { finish('connect_error'); }
  }
}
