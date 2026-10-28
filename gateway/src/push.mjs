import { readFileSync } from 'node:fs';
import { constants, createPrivateKey, sign } from 'node:crypto';
export function createPushSender(filename, category = 'MARKETING', testMessage = true) {
  if (!filename) return null;
  const account = JSON.parse(readFileSync(filename, 'utf8'));
  if (!/^\d+$/.test(account.project_id) || !account.key_id || !account.sub_account) throw Error('Invalid Push service account');
  const key = createPrivateKey(account.private_key);
  if (key.asymmetricKeyType !== 'rsa') throw Error('Push service account requires RSA');
  return async (token, routing, ttl) => {
    const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
    const now = Math.floor(Date.now() / 1000);
    const input = `${encode({ alg: 'PS256', typ: 'JWT', kid: account.key_id })}.${encode({ iss: account.sub_account,
      aud: 'https://oauth-login.cloud.huawei.com/oauth2/v3/token', iat: now, exp: now + 3600 })}`;
    const jwt = input + '.' + sign('sha256', Buffer.from(input), { key, padding: constants.RSA_PKCS1_PSS_PADDING, saltLength: 32 }).toString('base64url');
    const response = await fetch(`https://push-api.cloud.huawei.com/v3/${account.project_id}/messages:send`, {
      method: 'POST', redirect: 'error', signal: AbortSignal.timeout(15000),
      headers: { Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json', 'push-type': '0' },
      body: JSON.stringify({ payload: { notification: { category, title: routing.title || 'DSH Harmony',
        body: routing.code === 'run.failed' ? '任务执行失败' : routing.code === 'permission.required' ? '有任务需要确认' : '任务已完成',
        clickAction: { actionType: 0, data: routing } } }, target: { token: [token] }, pushOptions: { testMessage, ttl } })
    });
    const result = await response.json();
    if (!response.ok || String(result.code) !== '80000000') throw Error('Push provider rejected delivery');
  };
}

export async function flushJobs(db, send) {
  if (!send) return;
  const now = Date.now();
  db.prepare('DELETE FROM jobs WHERE expires <= ?').run(now);
  for (const job of db.prepare('SELECT * FROM jobs WHERE due <= ? ORDER BY id LIMIT 20').all(now)) {
    const device = db.prepare('SELECT token FROM devices WHERE id = ?').get(job.device);
    if (!device) { db.prepare('DELETE FROM jobs WHERE id = ?').run(job.id); continue; }
    try {
      await send(device.token, JSON.parse(job.payload), Math.max(1, Math.floor((job.expires - Date.now()) / 1000)));
      db.prepare('DELETE FROM jobs WHERE id = ?').run(job.id);
    } catch {
      const attempts = job.attempts + 1;
      if (attempts >= 8) db.prepare('DELETE FROM jobs WHERE id = ?').run(job.id);
      else db.prepare('UPDATE jobs SET attempts = ?, due = ? WHERE id = ?').run(attempts, Date.now() + Math.min(300000, 5000 * 2 ** attempts), job.id);
    }
  }
}
