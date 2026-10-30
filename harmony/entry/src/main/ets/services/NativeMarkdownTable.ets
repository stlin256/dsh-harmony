/** GFM table model used by the native transcript and file/Markdown reader. */
export class NativeMarkdownTable {
  headers: string[] = [];
  aligns: string[] = [];
  rows: string[][] = [];
}

function cells(line: string): string[] | null {
  let source = line.trim();
  if (!source || source.indexOf('|') < 0) return null;
  if (source.startsWith('|')) source = source.slice(1);
  if (source.endsWith('|') && !source.endsWith('\\|')) source = source.slice(0, -1);
  const result: string[] = [];
  let value = '';
  let escaped = false;
  let ticks = 0;
  for (let index = 0; index < source.length; index++) {
    const character = source.charAt(index);
    if (escaped) { value += character === '|' ? '|' : '\\' + character; escaped = false; continue; }
    if (character === '\\') { escaped = true; continue; }
    if (character === '`') ticks = ticks === 0 ? 1 : 0;
    if (character === '|' && ticks === 0) { result.push(value.trim()); value = ''; continue; }
    value += character;
  }
  if (escaped) value += '\\';
  result.push(value.trim());
  return result;
}

function alignment(value: string): string {
  const normalized = value.trim();
  if (!/^:?-{3,}:?$/.test(normalized)) return '';
  if (normalized.startsWith(':') && normalized.endsWith(':')) return 'center';
  if (normalized.endsWith(':')) return 'right';
  return 'left';
}

export function nativeMarkdownTable(source: string): NativeMarkdownTable | null {
  const lines = source.replace(/\r\n?/g, '\n').trim().split('\n');
  if (lines.length < 2) return null;
  const headers = cells(lines[0]);
  const delimiters = cells(lines[1]);
  if (!headers || !delimiters || !delimiters.length) return null;
  const aligns = delimiters.map(alignment);
  if (aligns.some((value: string) => !value)) return null;
  const count = aligns.length;
  const normalizedHeaders = headers.slice(0, count);
  while (normalizedHeaders.length < count) normalizedHeaders.push('');
  const table = new NativeMarkdownTable();
  table.headers = normalizedHeaders; table.aligns = aligns;
  for (let index = 2; index < lines.length; index++) {
    const values = cells(lines[index]);
    if (!values) break;
    const normalized = values.slice(0, count);
    while (normalized.length < count) normalized.push('');
    table.rows.push(normalized);
  }
  return table;
}
