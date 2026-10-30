/** Link classification and workspace-relative path resolution for native text. */

function cleanPath(value: string): string {
  return value.replace(/\\/g, '/');
}

export function nativeLinkKind(href: string): string {
  const value = href.trim();
  if (/^https?:/i.test(value)) return 'http';
  if (/^(?:mailto|tel):/i.test(value)) return 'external';
  if (value.startsWith('dsh-resource://file/session/')) return 'workspace';
  return 'file';
}

export function nativeFileTarget(href: string, cwd: string = ''): string {
  let target = href.trim();
  if (target.startsWith('<') && target.endsWith('>')) target = target.slice(1, -1);
  if (target.startsWith('dsh-resource://file/session/')) {
    const suffix = target.slice('dsh-resource://file/session/'.length);
    const split = suffix.indexOf('/');
    if (split > 0) target = suffix.slice(split + 1);
  }
  if (/^file:\/\//i.test(target)) {
    target = target.slice('file://'.length);
    if (target.startsWith('localhost/')) target = target.slice('localhost'.length);
    if (/^\/[A-Za-z]:\//.test(target)) target = target.slice(1);
  }
  const hash = target.lastIndexOf('#L');
  if (hash >= 0 && /^#L\d+(?:-L?\d+)?$/i.test(target.slice(hash))) {
    target = target.slice(0, hash);
  }
  target = cleanPath(decodeURIComponent(target));
  if (!cwd || target.startsWith('/') || target.startsWith('//') ||
      /^[A-Za-z]:\//.test(target)) return target;

  const source = cleanPath(cwd).replace(/\/+$/, '');
  const parts = source.split('/');
  const absolute = source.startsWith('/');
  if (absolute) parts.splice(0, 1);
  target.split('/').forEach((part: string): void => {
    if (!part || part === '.') return;
    if (part === '..') {
      if (parts.length > 0) parts.pop();
      return;
    }
    parts.push(part);
  });
  return (absolute ? '/' : '') + parts.join('/');
}
