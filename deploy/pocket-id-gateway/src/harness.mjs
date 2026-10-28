import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { digest } from './store.mjs';

export class Harness {
  constructor(config) { this.config = config; this.cached = null; this.pending = null; }
  invalidate() { this.cached = null; }
  async cookie() {
    const text = (await readFile(this.config.launchFile, 'utf8')).trim();
    const url = new URL(text);
    if (url.origin !== this.config.upstream.origin || url.pathname !== '/' || !url.search
        || url.username || url.password || url.hash) throw new Error('Invalid upstream launch URL');
    const fingerprint = digest(text);
    if (this.cached?.fingerprint === fingerprint && this.cached.until > Date.now()) return this.cached.value;
    if (this.pending) return this.pending;
    this.pending = this.exchange(url).then(value => {
      this.cached = { fingerprint, value, until: Date.now() + 240_000 };
      return value;
    }).finally(() => { this.pending = null; });
    return this.pending;
  }
  exchange(url) {
    return new Promise((resolve, reject) => {
      const request = http.get(url, { headers: { host: this.config.publicUrl.host }, timeout: 8000 }, response => {
        response.resume();
        const cookies = response.headers['set-cookie'] || [];
        const value = cookies.map(line => line.split(';', 1)[0]).filter(Boolean).join('; ');
        if (![302, 303, 307, 308].includes(response.statusCode) || !value) {
          reject(new Error('Upstream session exchange failed')); return;
        }
        resolve(value);
      });
      request.on('timeout', () => request.destroy(new Error('Upstream session exchange timed out')));
      request.on('error', reject);
    });
  }
}
