import { NativeMessage } from './NativeSessionModel';

export class NativeDiffRow {
  kind: string = 'context';
  text: string = '';
  oldLine: number = 0;
  newLine: number = 0;
}

export class NativeDiffDocument {
  matched: boolean = false;
  path: string = '';
  added: number = 0;
  removed: number = 0;
  rows: NativeDiffRow[] = [];
}

function countRows(document: NativeDiffDocument): void {
  document.added = document.rows.filter((row: NativeDiffRow): boolean => row.kind === 'add').length;
  document.removed = document.rows.filter((row: NativeDiffRow): boolean => row.kind === 'del').length;
}

function add(rows: NativeDiffRow[], kind: string, text: string, path: string,
  oldLine: number = 0, newLine: number = 0): void {
  const row = new NativeDiffRow();
  row.kind = kind; row.text = kind === 'path' ? path : text;
  row.oldLine = oldLine; row.newLine = newLine;
  rows.push(row);
}

function parsePatch(patch: string, fallbackPath: string): NativeDiffDocument {
  const out = new NativeDiffDocument();
  let path = fallbackPath;
  const lines = patch.replace(/\r\n/g, '\n').split('\n');
  let seen = false;
  let inHunk = false;
  let seenHunk = false;
  let oldNumber = 1;
  let newNumber = 1;
  for (let index = 0; index < lines.length; index++) {
    const line = lines[index];
    if (line.startsWith('*** Update File:') || line.startsWith('*** Add File:') ||
        line.startsWith('*** Delete File:')) {
      const nextPath = line.slice(line.indexOf(':') + 1).trim();
      if (nextPath) path = nextPath;
      if (path !== out.path) {
        add(out.rows, 'path', '', path);
        out.path = path;
      }
      seen = true; inHunk = false; seenHunk = false;
      oldNumber = 1; newNumber = 1; continue;
    }
    if (line.startsWith('*** Begin Patch') || line.startsWith('*** End Patch') ||
        line.startsWith('diff --git ') || line.startsWith('index ') ||
        line.startsWith('@@')) {
      if (line.startsWith('@@') && seenHunk) add(out.rows, 'gap', '⋯', path);
      inHunk = line.startsWith('@@');
      if (inHunk) {
        const hunk = /^@@\s+-(\d+)(?:,\d+)?\s+\+(\d+)(?:,\d+)?\s+@@/.exec(line);
        if (hunk) {
          oldNumber = Number(hunk[1]);
          newNumber = Number(hunk[2]);
        }
        seenHunk = true;
      }
      continue;
    }
    if (line.startsWith('--- ') || line.startsWith('+++ ')) {
      const target = line.slice(4).trim().replace(/^[ab]\//, '');
      if (target && target !== '/dev/null' && target !== path) {
        path = target;
        add(out.rows, 'path', '', path);
        out.path = path;
        seen = true;
        inHunk = false;
        seenHunk = false;
      }
      continue;
    }
    if (line.startsWith('+')) {
      add(out.rows, 'add', line.slice(1), path, 0, newNumber++);
      seen = true; continue;
    }
    if (line.startsWith('-')) {
      add(out.rows, 'del', line.slice(1), path, oldNumber++, 0);
      seen = true; continue;
    }
    if (line.startsWith(' ')) {
      add(out.rows, 'context', line.slice(1), path, oldNumber++, newNumber++);
      seen = true; continue;
    }
    if (inHunk && line) {
      add(out.rows, 'context', line, path, oldNumber++, newNumber++);
      seen = true;
    }
  }
  if (seen && !out.path) { out.path = fallbackPath || '变更'; add(out.rows, 'path', '', out.path); }
  out.matched = seen && out.rows.some((row: NativeDiffRow) => row.kind === 'add' || row.kind === 'del');
  countRows(out);
  return out;
}

function splitLines(value: string): string[] {
  if (!value) return [];
  const body = value.endsWith('\n') ? value.slice(0, -1) : value;
  return body.split('\n');
}

function lineDocument(oldText: string, newText: string, path: string): NativeDiffDocument {
  const out = new NativeDiffDocument();
  out.matched = true; out.path = path || '变更';
  add(out.rows, 'path', '', out.path);
  const before = splitLines(oldText);
  const after = splitLines(newText);
  if (before.length > 300 || after.length > 300) {
    before.forEach((line: string, index: number) => add(out.rows, 'del', line, out.path, index + 1, 0));
    after.forEach((line: string, index: number) => add(out.rows, 'add', line, out.path, 0, index + 1));
    countRows(out);
    return out;
  }
  const width = after.length + 1;
  const table: number[] = new Array<number>((before.length + 1) * width).fill(0);
  for (let left = before.length - 1; left >= 0; left--) {
    for (let right = after.length - 1; right >= 0; right--) {
      table[left * width + right] = before[left] === after[right] ?
        1 + table[(left + 1) * width + right + 1] :
        Math.max(table[(left + 1) * width + right], table[left * width + right + 1]);
    }
  }
  let left = 0; let right = 0;
  let oldNumber = 1; let newNumber = 1;
  while (left < before.length || right < after.length) {
    if (left < before.length && right < after.length && before[left] === after[right]) {
      add(out.rows, 'context', before[left], out.path, oldNumber++, newNumber++); left++; right++;
    } else if (right < after.length &&
      (left >= before.length || table[left * width + right + 1] >= table[(left + 1) * width + right])) {
      add(out.rows, 'add', after[right], out.path, 0, newNumber++); right++;
    } else {
      add(out.rows, 'del', before[left], out.path, oldNumber++, 0); left++;
    }
  }
  countRows(out);
  return out;
}
function appendDocument(target: NativeDiffDocument, value: NativeDiffDocument): void {
  value.rows.forEach((row: NativeDiffRow): void => {
    const copy = new NativeDiffRow();
    copy.kind = row.kind;
    copy.text = row.text;
    copy.oldLine = row.oldLine;
    copy.newLine = row.newLine;
    target.rows.push(copy);
  });
  if (!target.path && value.path) target.path = value.path;
}

function explicitDiffs(value: Object, fallbackPath: string): NativeDiffDocument {
  const combined = new NativeDiffDocument();
  if (!Array.isArray(value)) return combined;
  value.forEach((raw: Object): void => {
    const item = raw as Record<string, Object>;
    const path = typeof item['path'] === 'string' && item['path'] ?
      item['path'] as string : fallbackPath;
    const newText = item['newText'];
    if (typeof newText !== 'string') return;
    const oldText = item['oldText'];
    if (oldText !== null && oldText !== undefined && typeof oldText !== 'string') return;
    appendDocument(combined,
      lineDocument(typeof oldText === 'string' ? oldText : '', newText as string, path));
  });
  combined.matched = combined.rows.some((row: NativeDiffRow): boolean =>
    row.kind === 'add' || row.kind === 'del');
  countRows(combined);
  return combined;
}

function failedTool(tool: NativeMessage): boolean {
  if (tool.failed || tool.status === 'error' || tool.status === 'interrupted') return true;
  if (tool.outcome === 'failed' || tool.outcome === 'error' ||
      tool.outcome === 'interrupted' || tool.outcome === 'cancelled') return true;
  const result = tool.output || tool.error;
  return result.includes('AUTO_REVIEW_DENIED');
}

/** Extract only explicit patch/edit fields; arbitrary output wording is never enough. */
export function nativeDiff(tool: NativeMessage): NativeDiffDocument {
  if (failedTool(tool)) return new NativeDiffDocument();
  let args: Record<string, Object> = {};
  let meta: Record<string, Object> = {};
  try { args = JSON.parse(tool.args || '{}') as Record<string, Object>; } catch (_) {}
  try { meta = JSON.parse(tool.metaRaw || '{}') as Record<string, Object>; } catch (_) {}
  const fallbackPath = typeof args['file_path'] === 'string' ? args['file_path'] as string :
    typeof args['path'] === 'string' ? args['path'] as string : '';
  if (args['diffs'] !== undefined) {
    const result = explicitDiffs(args['diffs'], fallbackPath);
    if (result.matched) return result;
  }
  if (meta['diffs'] !== undefined) {
    const result = explicitDiffs(meta['diffs'], fallbackPath);
    if (result.matched) return result;
  }
  for (const field of ['patch', 'diff']) {
    const value = args[field];
    if (typeof value === 'string' && value.trim()) return parsePatch(value, fallbackPath);
  }
  const oldText = args['oldText'];
  const newText = args['newText'];
  if ((oldText === null || typeof oldText === 'string') && typeof newText === 'string') {
    return lineDocument(typeof oldText === 'string' ? oldText : '', newText as string, fallbackPath);
  }
  const metadataDiff = meta['diff'];
  if (typeof metadataDiff === 'string' && metadataDiff.trim()) return parsePatch(metadataDiff, fallbackPath);
  const output = tool.output || '';
  if (output.includes('*** Begin Patch') || output.includes('diff --git ') ||
      /^@@\s/m.test(output)) return parsePatch(output, fallbackPath);
  return new NativeDiffDocument();
}

export function nativeDiffText(rows: NativeDiffRow[]): string {
  return rows.map((row: NativeDiffRow): string => {
    if (row.kind === 'add') return '+ ' + row.text;
    if (row.kind === 'del') return '- ' + row.text;
    if (row.kind === 'context') return '  ' + row.text;
    return row.text;
  }).join('\n');
}
