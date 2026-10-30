import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { NativeFileBytes, NativeFileStat, NativeHarnessClient } from './NativeHarnessClient';

const fileWindowBytes: number = 2 * 1024 * 1024;

export class NativeFileContent {
  bytes: Uint8Array = new Uint8Array();
  version: string = '';
  totalBytes: number = 0;
}

function fileName(value: string): string {
  const parts = value.replace(/\\/g, '/').split('/');
  const name = (parts[parts.length - 1] || 'workspace-file')
    .replace(/[\u0000-\u001f\\/:*?"<>|]/g, '_').trim();
  return name || 'workspace-file';
}

/** Read-only byte transfer for workspace previews and explicit local downloads. */
export class NativeFileTransfer {
  static async readComplete(client: NativeHarnessClient, sessionId: string, path: string,
    maxBytes: number, expectedVersion: string = '', expectedBytes: number = -1): Promise<NativeFileContent> {
    const chunks: Uint8Array[] = [];
    let total: number = 0;
    let offset: number = 0;
    let version: string = '';
    let reportedBytes: number = -1;
    while (true) {
      const window: NativeFileBytes = await client.readFileBytes(sessionId, path, '', offset, fileWindowBytes,
        version || expectedVersion, reportedBytes >= 0 ? reportedBytes : expectedBytes);
      if (!version) version = window.version;
      if (!window.version || window.version !== version) throw new Error('File changed while reading');
      if (window.bytes >= 0) reportedBytes = window.bytes;
      if (reportedBytes > maxBytes) throw new Error('File is too large to preview');
      if (total + window.data.byteLength > maxBytes) throw new Error('File is too large to preview');
      if (window.data.byteLength > 0) {
        chunks.push(window.data);
        total += window.data.byteLength;
      }
      offset += window.data.byteLength;
      if (window.eof) break;
      if (window.data.byteLength === 0) throw new Error('Incomplete file window');
    }
    const bytes = new Uint8Array(total);
    let cursor: number = 0;
    chunks.forEach((part: Uint8Array): void => {
      bytes.set(part, cursor);
      cursor += part.byteLength;
    });
    const content = new NativeFileContent();
    content.bytes = bytes;
    content.version = version;
    content.totalBytes = reportedBytes >= 0 ? reportedBytes : total;
    if (reportedBytes >= 0 && total !== reportedBytes) throw new Error('Incomplete file read');
    return content;
  }

  static async download(context: common.UIAbilityContext, client: NativeHarnessClient,
    sessionId: string, path: string): Promise<boolean> {
    const stat: NativeFileStat = await client.statFile(sessionId, path);
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [fileName(path)];
    const chosen = await new picker.DocumentViewPicker(context).save(options);
    if (!chosen.length) return false;
    const destination = fileIo.openSync(chosen[0],
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    let offset: number = 0;
    let expectedVersion: string = stat.version;
    try {
      while (true) {
        const window: NativeFileBytes = await client.readFileBytes(sessionId, path, '', offset, fileWindowBytes,
          expectedVersion, stat.bytes);
        if (!window.version || window.version !== expectedVersion) throw new Error('File changed while downloading');
        if (window.data.byteLength > 0) fileIo.writeSync(destination.fd, window.data.buffer as ArrayBuffer);
        offset += window.data.byteLength;
        if (window.eof) break;
        if (window.data.byteLength === 0) throw new Error('Incomplete file window');
      }
      return true;
    } finally {
      fileIo.closeSync(destination);
    }
  }
}
