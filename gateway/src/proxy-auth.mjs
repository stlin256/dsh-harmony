import { createHash, timingSafeEqual } from 'node:crypto';

/** Only the loopback OIDC adapter may attest an already verified session. */
export function proxyAuthentication(secret, db) {
  if (typeof secret !== 'string' || secret.length < 32) throw Error('Configure PROXY_SECRET');
  const expected = Buffer.from(secret);
  return req => {
    const supplied = Buffer.from(req.headers['x-dsh-proxy-secret'] || '');
    if (!['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(req.socket.remoteAddress) ||
        supplied.length !== expected.length || !timingSafeEqual(supplied, expected)) return false;
    const owner = req.headers['x-dsh-session'];
    const expiry = Number(req.headers['x-dsh-session-expires']);
    const upstream = req.headers['x-dsh-upstream-cookie'];
    if (typeof owner === 'string' && /^[A-Za-z0-9_-]{20,128}$/.test(owner) && Number.isSafeInteger(expiry) &&
        expiry > Date.now() && expiry <= Date.now() + 91 * 86400000) {
      req.pocketOwner = createHash('sha256').update('oidc:' + owner).digest('hex');
      if (typeof upstream === 'string' && upstream.length > 0 && upstream.length <= 16384 && !/[\r\n]/.test(upstream)) req.pocketUpstreamCookie = upstream;
      db.prepare('INSERT INTO sessions VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET expires=excluded.expires').run(req.pocketOwner, expiry);
    }
    return true;
  };
}
