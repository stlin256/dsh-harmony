import { execFileSync } from 'node:child_process';
const git = args => execFileSync('git', args, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
const forbidden = (process.env.DSH_PRIVATE_HOSTS || '').split(',').map(s => s.trim().toLowerCase()).filter(Boolean);
const failures = [];
const inspect = (text, label) => {
  if (forbidden.some(value => text.toLowerCase().includes(value))) failures.push(label + ': private host');
  if (/-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/.test(text)) failures.push(label + ': private key');
  if (/\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})\b/.test(text)) failures.push(label + ': access token');
  if (/\b(?:10(?:\.\d{1,3}){3}|192\.168(?:\.\d{1,3}){2}|172\.(?:1[6-9]|2\d|3[01])(?:\.\d{1,3}){2})\b/.test(text)) failures.push(label + ': private network address');
  if (/\/(?:home|Users)\/[A-Za-z0-9_.-]+\//.test(text)) failures.push(label + ': personal filesystem path');
};
for (const commit of git(['rev-list', '--all']).trim().split('\n').filter(Boolean)) {
  inspect(git(['show', '-s', '--format=%B%n%an%n%ae%n%cn%n%ce', commit]), commit.slice(0, 8) + ' metadata');
  for (const row of git(['ls-tree', '-r', commit]).trim().split('\n').filter(Boolean)) {
    const match = /^\d+ blob ([a-f0-9]+)\t(.+)$/.exec(row);
    if (!match) continue;
    const [, object, filename] = match;
    if (/\.(?:p12|p7b|keystore|sqlite|pem)$/.test(filename) || /(?:^|\/)\.env$/.test(filename)) failures.push(filename + ': forbidden artifact');
    inspect(git(['cat-file', 'blob', object]), commit.slice(0, 8) + ':' + filename);
  }
}
// Scan staged source too, before making the next commit.
for (const file of git(['diff', '--cached', '--name-only', '--diff-filter=ACMR']).trim().split('\n').filter(Boolean)) inspect(git(['show', ':' + file]), 'staged:' + file);
if (failures.length) { console.error([...new Set(failures)].join('\n')); process.exitCode = 1; }
else console.log('Publication checks passed for reachable history and staged content');
