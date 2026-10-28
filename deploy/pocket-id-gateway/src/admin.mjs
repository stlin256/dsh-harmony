import { configuration } from './config.mjs';
import { Store } from './store.mjs';
process.umask(0o077);
const store = new Store(configuration());
try {
  const [action, id] = process.argv.slice(2);
  if (action === 'list') {
    store.prune(); console.log(JSON.stringify(store.list(), null, 2));
  } else if (action === 'revoke' && /^[a-f0-9]{64}$/.test(id || '')) {
    store.revoke(id); console.log('Session revoked. Associated streams close within 15 seconds.');
  } else if (action === 'revoke-all') {
    for (const row of store.list()) store.revoke(row.id);
    console.log('All sessions revoked. Associated streams close within 15 seconds.');
  } else {
    console.error('Usage: admin.mjs list | revoke <session-id> | revoke-all'); process.exitCode = 2;
  }
} finally { store.close(); }
