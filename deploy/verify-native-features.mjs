/** Operator-only smoke test for native file and session-order contracts. */
import { readFile } from 'node:fs/promises';

const launch = new URL((await readFile(process.argv[2], 'utf8')).trim());
const origin = launch.origin;
const token = launch.searchParams.get('token');
if (!token) throw Error('Launch credential unavailable');

let cookie = '';
const call = async (path, body) => {
  const response = await fetch(origin + path, {
    method: body === undefined ? 'GET' : 'POST',
    redirect: 'error',
    signal: AbortSignal.timeout(15000),
    headers: {
      Origin: origin,
      Cookie: cookie,
      'Content-Type': 'application/json'
    },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  if (!response.ok) throw Error('Probe rejected: ' + path + ' HTTP ' + response.status);
  return response;
};

const json = async (path, body) => (await call(path, body)).json();
const login = await call('/pocket/api/auth/native', { token });
cookie = login.headers.getSetCookie().map(value => value.split(';')[0]).join('; ');
if (!cookie) throw Error('No native cookie');

try {
  const [sessions, workspaces] = await Promise.all([
    json('/pocket/api/native/sessions'),
    json('/pocket/api/native/workspaces')
  ]);
  if (sessions.protocol !== 2 || !Array.isArray(sessions.items)) {
    throw Error('Unexpected session response');
  }

  const byId = new Map(sessions.items.map(value => [value.id, value]));
  const ordered = workspaces.items.find(workspace =>
    workspace.sessionIds.filter(id => byId.get(id)?.blank !== true).length >= 2);
  let ordering = 'skipped';
  if (ordered) {
    const ids = ordered.sessionIds.filter(id => byId.get(id)?.blank !== true);
    await call('/pocket/api/native/operation', {
      operation: 'sessionInsertBefore',
      workspaceId: ordered.workspaceId,
      sessionId: ids[0],
      beforeSessionId: ids[1]
    });
    ordering = 'ok';
  }

  let files = 0;
  let firstFile = null;
  for (const session of sessions.items) {
    const queue = session.cwd ? [session.cwd, ''] : [''];
    const visited = new Set();
    while (queue.length && visited.size < 32 && !firstFile) {
      const path = queue.shift();
      if (visited.has(path)) continue;
      visited.add(path);
      let listing;
      try {
        listing = await json('/pocket/api/native/file/list', {
          sessionId: session.id,
          path
        });
      } catch {
        continue;
      }
      const currentPath = listing.path || path;
      files += listing.entries.filter(entry => entry.type === 'file').length;
      const file = listing.entries.find(entry =>
        entry.type === 'file' && (entry.size ?? 0) <= 2 * 1024 * 1024);
      if (file) {
        firstFile = {
          sessionId: session.id,
          path: currentPath ? currentPath.replace(/\/+$/, '') + '/' + file.name : file.name
        };
        break;
      }
      listing.entries
        .filter(entry => entry.type === 'directory')
        .forEach(entry => queue.push(currentPath ? currentPath.replace(/\/+$/, '') + '/' + entry.name : entry.name));
    }
    if (firstFile) break;
  }

  if (!firstFile) throw Error('No readable workspace file found for binary probe');
  const stat = await json('/pocket/api/native/file/stat', firstFile);
  if (!stat.version) throw Error('Invalid file stat');
  const binary = await call('/pocket/api/native/file/bytes', {
    ...firstFile,
    offset: 0,
    length: 64
  });
  const encoded = (binary.headers.get('x-dsh-file-window') || '')
    .replace(/-/g, '+')
    .replace(/_/g, '/');
  const metadata = JSON.parse(Buffer.from(
    encoded + '='.repeat((4 - encoded.length % 4) % 4),
    'base64'
  ).toString());
  const data = new Uint8Array(await binary.arrayBuffer());
  if (metadata.protocol !== 1 || metadata.length !== data.length ||
      metadata.version !== stat.version) {
    throw Error('Invalid binary file response');
  }

  console.log(JSON.stringify({
    nativeLogin: true,
    sessions: sessions.items.length,
    workspaces: workspaces.items.length,
    ordering,
    directoryFilesSeen: files,
    stat: true,
    bytes: data.length
  }));
} finally {
  await call('/pocket/api/logout', {});
}
