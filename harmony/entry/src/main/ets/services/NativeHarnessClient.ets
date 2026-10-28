import { http, webSocket } from '@kit.NetworkKit';
import { webview } from '@kit.ArkWeb';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { NativeFrame, NativeSessionList, NativeSessionModel } from './NativeSessionModel';

export class NativeHttpError extends Error {
  status: number;
  constructor(status: number) { super(status === 401 ? '请先登录工作空间' : '请求失败或结果未确认，请刷新核对'); this.status = status; }
}
export class GatewayState {
  mode: string = '';
  authOrigin: string = '';
  authenticated: boolean = false;
  pushConfigured: boolean = false;
}
export class NativeImageDraft { id: string = ''; name: string = ''; mediaType: string = ''; data: string = ''; }
export class NativeCreatedSession { id: string = ''; }

export class NativeHarnessClient {
  private origin: string;
  private socket: webSocket.WebSocket | null = null;
  private generation: number = 0;
  readonly images: Map<string, NativeImageDraft[]> = new Map<string, NativeImageDraft[]>();
  readonly drafts: Map<string, string> = new Map<string, string>();
  readonly uncertain: Set<string> = new Set<string>();
  /** In-memory only: retain visible chat history across session switches and settings. */
  readonly models: Map<string, NativeSessionModel> = new Map<string, NativeSessionModel>();
  selectedId: string = '';

  constructor(origin: string) { this.origin = origin; }

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
    if (!/^\/pocket\/api\/(?:state|overview|logout|device|auth\/(?:none|native)|native\/(?:sessions|create|page|prompt|cancel|operation|answer))$/.test(path)) throw new Error('Unsupported endpoint');
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
        if (status < 200 || status >= 300) throw new NativeHttpError(status);
        await end;
        const buffer = new Uint8Array(bytes);
        let offset: number = 0;
        chunks.forEach((part: Uint8Array) => { buffer.set(part, offset); offset += part.byteLength; });
        return util.TextDecoder.create('utf-8').decodeToString(buffer);
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

  async state(): Promise<GatewayState> { return JSON.parse(await this.request('/pocket/api/state')) as GatewayState; }
  async loginNative(token: string): Promise<void> {
    await this.request('/pocket/api/auth/native', http.RequestMethod.POST, JSON.stringify({ token: token }));
  }
  async sessions(): Promise<NativeSessionList> { return JSON.parse(await this.request('/pocket/api/native/sessions')) as NativeSessionList; }
  async create(cwd: string = '', agentPreset: string = ''): Promise<string> {
    const result = JSON.parse(await this.request('/pocket/api/native/create', http.RequestMethod.POST,
      JSON.stringify({ requestId: util.generateRandomUUID(), cwd: cwd || undefined, agentPreset: agentPreset || undefined }))) as NativeCreatedSession;
    return result.id;
  }
  async page(id: string, before: number, throughSeq: number = -1): Promise<NativeFrame> {
    return JSON.parse(await this.request('/pocket/api/native/page', http.RequestMethod.POST,
      JSON.stringify({ sessionId: id, beforeSeq: before, throughSeq: throughSeq }))) as NativeFrame;
  }
  async prompt(id: string, text: string, mode: string = 'queue', images: NativeImageDraft[] = []): Promise<void> {
    this.uncertain.add(id);
    try {
      await this.request('/pocket/api/native/prompt', http.RequestMethod.POST,
        JSON.stringify({ sessionId: id, requestId: util.generateRandomUUID(), text: text, mode: mode, images: images }));
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
    this.models.clear(); this.drafts.clear(); this.images.clear(); this.uncertain.clear(); this.selectedId = '';
  }
  async follow(id: string, receive: (frame: NativeFrame) => void, ended: () => void): Promise<void> {
    if (!/^[A-Za-z0-9_-]{1,160}$/.test(id)) throw new Error('Invalid session');
    this.pause();
    const generation = this.generation;
    const cookie = await this.cookie();
    if (generation !== this.generation) return;
    const socket = webSocket.createWebSocket(); this.socket = socket;
    let finished: boolean = false;
    const finish = (): void => {
      if (generation !== this.generation || finished) return;
      finished = true; socket.close().catch(() => {}); ended();
    };
    socket.on('message', (error: BusinessError, data: string | ArrayBuffer): void => {
      if (error || generation !== this.generation || finished) return;
      try {
        const text = typeof data === 'string' ? data : util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(data));
        receive(JSON.parse(text) as NativeFrame);
      } catch (_) { finish(); }
    });
    socket.on('close', finish);
    socket.on('error', finish);
    try { await socket.connect(this.origin.replace(/^https:/, 'wss:') + '/pocket/native/live?sessionId=' + encodeURIComponent(id),
      { header: { Origin: this.origin, Cookie: cookie } }); }
    catch (_) { finish(); }
  }
}
