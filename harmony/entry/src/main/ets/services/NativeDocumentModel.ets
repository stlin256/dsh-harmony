const imageExtensions: Set<string> = new Set<string>([
  'png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp', 'ico', 'dng', 'heic', 'heif'
]);

const codeLanguages: Map<string, string> = new Map<string, string>([
  ['js', 'javascript'], ['mjs', 'javascript'], ['cjs', 'javascript'],
  ['jsx', 'jsx'], ['ts', 'typescript'], ['tsx', 'tsx'], ['ets', 'arkts'],
  ['json', 'json'], ['sh', 'shell'], ['bash', 'bash'], ['zsh', 'shell'],
  ['ps1', 'powershell'], ['py', 'python'], ['go', 'go'], ['rs', 'rust'],
  ['java', 'java'], ['kt', 'kotlin'], ['kts', 'kotlin'], ['swift', 'swift'],
  ['c', 'c'], ['h', 'c'], ['cc', 'cpp'], ['cpp', 'cpp'], ['cxx', 'cpp'],
  ['hpp', 'cpp'], ['cs', 'cs'], ['html', 'html'], ['htm', 'html'],
  ['xml', 'xml'], ['svg', 'svg'], ['css', 'css'], ['scss', 'scss'],
  ['less', 'less'], ['yaml', 'yaml'], ['yml', 'yaml'], ['toml', 'toml'],
  ['sql', 'sql'], ['md', 'markdown'], ['markdown', 'markdown'],
  ['diff', 'diff'], ['patch', 'patch'], ['rb', 'ruby']
]);

export class NativeDocumentDescriptor {
  kind: string = 'unknown';
  language: string = '';
  defaultMode: string = 'code';
  canToggle: boolean = false;
  canPreview: boolean = false;
}

export class NativeSourceLine {
  number: number = 1;
  text: string = '';
}

export class NativeMarkdownBlock {
  kind: string = 'paragraph';
  text: string = '';
  language: string = '';
  level: number = 0;
}

export function nativeDocumentExtension(path: string): string {
  const clean = path.replace(/\\/g, '/');
  const parts = clean.split('/');
  const name = parts[parts.length - 1] || '';
  const dot = name.lastIndexOf('.');
  if (dot < 0 || dot === name.length - 1) return '';
  return name.slice(dot + 1).toLowerCase();
}

export function nativeDocumentDescriptor(path: string): NativeDocumentDescriptor {
  const descriptor = new NativeDocumentDescriptor();
  const extension = nativeDocumentExtension(path);
  if (extension === 'svg') {
    descriptor.kind = 'svg';
    descriptor.language = 'svg';
    descriptor.defaultMode = 'preview';
    descriptor.canToggle = true;
    descriptor.canPreview = true;
    return descriptor;
  }
  if (extension === 'md' || extension === 'markdown') {
    descriptor.kind = 'markdown';
    descriptor.language = 'markdown';
    descriptor.defaultMode = 'preview';
    descriptor.canToggle = true;
    descriptor.canPreview = true;
    return descriptor;
  }
  if (imageExtensions.has(extension)) {
    descriptor.kind = 'image';
    descriptor.defaultMode = 'preview';
    descriptor.canPreview = true;
    return descriptor;
  }
  if (codeLanguages.has(extension)) {
    descriptor.kind = 'code';
    descriptor.language = codeLanguages.get(extension) || '';
    return descriptor;
  }
  return descriptor;
}

export function nativeSourceLines(source: string, startNumber: number = 1): NativeSourceLine[] {
  const normalized = source.replace(/\r\n|\r/g, '\n');
  const raw = normalized.split('\n');
  const start = Number.isSafeInteger(startNumber) && startNumber > 0 ? startNumber : 1;
  return raw.map((text: string, index: number): NativeSourceLine => {
    const line = new NativeSourceLine();
    line.number = start + index;
    line.text = text;
    return line;
  });
}

function pushMarkdown(blocks: NativeMarkdownBlock[], kind: string, text: string,
  level: number = 0, language: string = ''): void {
  if (kind !== 'code' && !text.trim()) return;
  const block = new NativeMarkdownBlock();
  block.kind = kind;
  block.text = text;
  block.level = level;
  block.language = language;
  blocks.push(block);
}

function tableDelimiter(line: string): boolean {
  const value = line.trim();
  if (!value.includes('|')) return false;
  return /^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?$/.test(value);
}

/** A bounded Markdown block projection for file preview, independent of ArkUI. */
export function nativeMarkdownBlocks(source: string): NativeMarkdownBlock[] {
  const lines = source.replace(/\r\n|\r/g, '\n').split('\n');
  const blocks: NativeMarkdownBlock[] = [];
  let index = 0;
  while (index < lines.length) {
    const line = lines[index];
    if (!line.trim()) {
      index++;
      continue;
    }
    const fence = /^\s*(```+|~~~+)\s*([^ ]*)\s*$/.exec(line);
    if (fence) {
      const marker = fence[1][0];
      const language = fence[2] || '';
      const body: string[] = [];
      index++;
      while (index < lines.length && !new RegExp('^\\s*' + marker + '{3,}\\s*$').test(lines[index])) {
        body.push(lines[index]);
        index++;
      }
      if (index < lines.length) index++;
      pushMarkdown(blocks, 'code', body.join('\n'), 0, language);
      continue;
    }
    const heading = /^(#{1,6})\s+(.+)$/.exec(line);
    if (heading) {
      pushMarkdown(blocks, 'heading', heading[2], heading[1].length);
      index++;
      continue;
    }
    if (/^\s*>/.test(line)) {
      const quoted: string[] = [];
      while (index < lines.length && /^\s*>/.test(lines[index])) {
        quoted.push(lines[index].replace(/^\s*>\s?/, ''));
        index++;
      }
      pushMarkdown(blocks, 'quote', quoted.join('\n'));
      continue;
    }
    if (line.includes('|') && index + 1 < lines.length && tableDelimiter(lines[index + 1])) {
      const table: string[] = [line, lines[index + 1]];
      index += 2;
      while (index < lines.length && lines[index].trim() && lines[index].includes('|')) {
        table.push(lines[index]);
        index++;
      }
      pushMarkdown(blocks, 'table', table.join('\n'));
      continue;
    }
    const paragraph: string[] = [];
    while (index < lines.length && lines[index].trim() &&
      !/^\s*(```+|~~~+)/.test(lines[index]) && !/^(#{1,6})\s+/.test(lines[index]) &&
      !/^\s*>/.test(lines[index]) &&
      !(lines[index].includes('|') && index + 1 < lines.length && tableDelimiter(lines[index + 1]))) {
      paragraph.push(lines[index]);
      index++;
    }
    pushMarkdown(blocks, 'paragraph', paragraph.join('\n'));
  }
  return blocks;
}
