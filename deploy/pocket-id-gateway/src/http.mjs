export const SESSION_COOKIE = '__Host-hpg_session';
export const FLOW_COOKIE = '__Host-hpg_flow';
export function cookies(request) {
  const result = Object.create(null);
  for (const item of (request.headers.cookie || '').split(';')) {
    const i = item.indexOf('=');
    if (i > 0) {
      const key = item.slice(0, i).trim();
      if (Object.hasOwn(result, key)) { result[key] = ''; continue; }
      result[key] = item.slice(i + 1).trim();
    }
  }
  return result;
}
export const cookie = (name, value, age) => `${name}=${value}; Path=/; Max-Age=${Math.max(0, Math.floor(age / 1000))}; Secure; HttpOnly; SameSite=Lax`;
export function headers(response) {
  response.setHeader('Cache-Control', 'no-store');
  response.setHeader('Referrer-Policy', 'no-referrer');
  response.setHeader('X-Content-Type-Options', 'nosniff');
  response.setHeader('X-Frame-Options', 'DENY');
}
export function reply(response, status, body, type = 'text/plain; charset=utf-8') {
  headers(response); response.writeHead(status, { 'Content-Type': type }); response.end(body);
}
export function redirect(response, path, setCookies) {
  headers(response);
  if (setCookies) response.setHeader('Set-Cookie', setCookies);
  response.writeHead(303, { Location: path }); response.end();
}
export const originOK = (request, config) => request.headers.origin === config.publicUrl.origin;
export function requestURL(request, config) {
  if (request.headers.host !== config.publicUrl.host || !request.url?.startsWith('/') || request.url.startsWith('//') || request.url.includes('\\')) {
    throw new Error('Invalid request authority');
  }
  const url = new URL(request.url, config.publicUrl);
  if (url.origin !== config.publicUrl.origin) throw new Error('Invalid request origin');
  return url;
}
export function landing() {
  return `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Harness · Passkey access</title><style>
:root{color-scheme:dark}*{box-sizing:border-box}body{margin:0;min-height:100svh;display:grid;place-items:center;background:#0c1523;color:#edf4fd;font:16px system-ui,sans-serif;padding:24px}.card{max-width:570px;padding:48px;border:1px solid #2b4059;border-radius:24px;background:#142237}.tag{color:#6bdfd1;font-size:12px;letter-spacing:.16em}h1{font-size:42px;line-height:1.1;letter-spacing:-.04em;margin:24px 0 16px}p{color:#aebece;line-height:1.7}a{display:inline-block;margin-top:20px;padding:14px 24px;border-radius:12px;background:#7de6ce;color:#10241e;font-weight:700;text-decoration:none}.note{font-size:12px;margin-top:30px}</style>
<main class="card"><div class="tag">HARNESS PASSKEY GATEWAY</div><h1>Your workspace.<br>Your passkey.</h1><p>Sign in with a registered device to open your agent workspace.</p><p>使用已登记设备的通行密钥，进入你的 Agent 工作区。</p><a href="/_gateway/login">Continue with passkey · 使用通行密钥</a><p class="note">No account yet? Ask your administrator to enroll your device.</p></main></html>`;
}
