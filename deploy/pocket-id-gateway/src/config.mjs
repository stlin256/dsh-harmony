import { isIP } from 'node:net';

export function configuration(env = process.env) {
  const required = (name) => {
    const value = env[name]?.trim();
    if (!value || value.includes('CHANGE_ME')) throw new Error(`Configure ${name}`);
    return value;
  };
  const secureOrigin = (name) => {
    const u = new URL(required(name));
    if (u.protocol !== 'https:' || u.username || u.password || u.search || u.hash || u.pathname !== '/') {
      throw new Error(`${name} must be an HTTPS origin`);
    }
    return u;
  };
  const integer = (name, fallback, min, max) => {
    const value = Number(env[name] ?? fallback);
    if (!Number.isInteger(value) || value < min || value > max) throw new Error(`Invalid ${name}`);
    return value;
  };
  const publicUrl = secureOrigin('PUBLIC_URL');
  const issuer = secureOrigin('OIDC_ISSUER');
  const upstream = new URL(env.HARNESS_UPSTREAM || 'http://127.0.0.1:3080');
  if (upstream.protocol !== 'http:' || !['127.0.0.1', 'localhost', '[::1]'].includes(upstream.hostname)
      || upstream.username || upstream.password || upstream.pathname !== '/' || upstream.search || upstream.hash) {
    throw new Error('HARNESS_UPSTREAM must be a loopback HTTP origin');
  }
  const host = env.LISTEN_HOST || '127.0.0.1';
  const privateIPv4 = (value) => {
    if (isIP(value) !== 4) return false;
    const [a, b] = value.split('.').map(Number);
    return a === 10 || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168);
  };
  const trustedProxy = env.TRUSTED_PROXY_IP?.trim() || null;
  if (trustedProxy && !privateIPv4(trustedProxy)) throw new Error('TRUSTED_PROXY_IP must be a private IPv4 address');
  if (!['127.0.0.1', '::1'].includes(host) && !(privateIPv4(host) && trustedProxy)) {
    throw new Error('A private listener requires an explicit trusted proxy');
  }
  const subjects = new Set(required('ALLOWED_SUBJECTS').split(',').map(x => x.trim()).filter(Boolean));
  if (!subjects.size) throw new Error('An explicit subject allowlist is required');
  const maxDays = integer('SESSION_MAX_DAYS', 90, 1, 90);
  const idleDays = integer('SESSION_IDLE_DAYS', 7, 1, maxDays);
  return {
    publicUrl, issuer, upstream, host, subjects, trustedProxy,
    clientId: required('OIDC_CLIENT_ID'), clientSecret: required('OIDC_CLIENT_SECRET'),
    port: integer('LISTEN_PORT', 4180, 1024, 65535),
    database: required('DATABASE_PATH'), launchFile: required('HARNESS_LAUNCH_URL_FILE'),
    maxAge: maxDays * 86400_000, idleAge: idleDays * 86400_000,
    uploadLimit: integer('MAX_UPLOAD_MIB', 128, 1, 1024) * 1024 * 1024,
  };
}
