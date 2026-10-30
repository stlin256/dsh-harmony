import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { NativeImageAttachment } from './NativeSessionModel';

/** App-private raster cache keyed by the one-way login scope and attachment identity. */
export class NativeAttachmentCache {
  private static readonly maxBytes: number = 32 * 1024 * 1024;
  private static readonly scopeQuota: number = 256 * 1024 * 1024;

  private static hash(value: string): string {
    let result = 2166136261;
    for (let index = 0; index < value.length; index++) {
      result ^= value.charCodeAt(index);
      result = Math.imul(result, 16777619);
    }
    return (result >>> 0).toString(16);
  }

  private static directory(context: common.UIAbilityContext): string {
    const path = context.filesDir + '/native-attachment-cache';
    if (!fileIo.accessSync(path)) fileIo.mkdirSync(path, true);
    return path;
  }

  private static key(scope: string, sessionId: string,
    attachment: NativeImageAttachment): string {
    return NativeAttachmentCache.hash(scope) + '-' +
      NativeAttachmentCache.hash(sessionId + ':' + attachment.attachmentId) + '-' +
      NativeAttachmentCache.hash(attachment.name + ':' + attachment.mediaType + ':' +
        String(attachment.bytes));
  }

  private static path(context: common.UIAbilityContext, scope: string, sessionId: string,
    attachment: NativeImageAttachment): string {
    return NativeAttachmentCache.directory(context) + '/' +
      NativeAttachmentCache.key(scope, sessionId, attachment) + '.bin';
  }

  static async load(context: common.UIAbilityContext, scope: string, sessionId: string,
    attachment: NativeImageAttachment): Promise<Uint8Array | null> {
    const path = NativeAttachmentCache.path(context, scope, sessionId, attachment);
    let file: fileIo.File | null = null;
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(file.fd);
      const length = Number(stat.size);
      if (!Number.isSafeInteger(length) || length <= 0 || length > NativeAttachmentCache.maxBytes) {
        throw new Error('Invalid cached attachment');
      }
      const buffer = new ArrayBuffer(length);
      let offset = 0;
      while (offset < length) {
        const count = fileIo.readSync(file.fd, buffer, {
          offset: offset,
          length: length - offset
        });
        if (count <= 0) throw new Error('Incomplete cached attachment');
        offset += count;
      }
      const now = new Date();
      fileIo.utimes(path, now.getTime());
      return new Uint8Array(buffer);
    } catch (_) {
      try { if (fileIo.accessSync(path)) fileIo.unlinkSync(path); } catch (_) {}
      return null;
    } finally {
      if (file) fileIo.closeSync(file);
    }
  }

  static async save(context: common.UIAbilityContext, scope: string, sessionId: string,
    attachment: NativeImageAttachment, bytes: Uint8Array): Promise<void> {
    if (!bytes.byteLength || bytes.byteLength > NativeAttachmentCache.maxBytes) return;
    const path = NativeAttachmentCache.path(context, scope, sessionId, attachment);
    const temporary = path + '.tmp-' + util.generateRandomUUID();
    let file: fileIo.File | null = null;
    try {
      file = fileIo.openSync(temporary,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, bytes.buffer as ArrayBuffer);
      fileIo.closeSync(file);
      file = null;
      fileIo.renameSync(temporary, path);
      await NativeAttachmentCache.trimScope(context, scope);
    } finally {
      if (file) fileIo.closeSync(file);
      try { if (fileIo.accessSync(temporary)) fileIo.unlinkSync(temporary); } catch (_) {}
    }
  }

  static async clearScope(context: common.UIAbilityContext, scope: string): Promise<void> {
    const prefix = NativeAttachmentCache.hash(scope) + '-';
    const directory = NativeAttachmentCache.directory(context);
    try {
      for (const name of fileIo.listFileSync(directory)) {
        if (!name.startsWith(prefix)) continue;
        try { fileIo.unlinkSync(directory + '/' + name); } catch (_) {}
      }
    } catch (_) {}
  }

  private static async trimScope(context: common.UIAbilityContext, scope: string): Promise<void> {
    const prefix = NativeAttachmentCache.hash(scope) + '-';
    const directory = NativeAttachmentCache.directory(context);
    const rows: Array<[string, number, number]> = [];
    let total = 0;
    try {
      for (const name of fileIo.listFileSync(directory)) {
        if (!name.startsWith(prefix)) continue;
        try {
          const stat = fileIo.statSync(directory + '/' + name);
          const size = Number(stat.size);
          if (!Number.isFinite(size) || size < 0) continue;
          total += size;
          rows.push([name, size, stat.mtime]);
        } catch (_) {}
      }
    } catch (_) {
      return;
    }
    if (total <= NativeAttachmentCache.scopeQuota) return;
    rows.sort((left: [string, number, number], right: [string, number, number]): number =>
      left[2] - right[2]);
    for (const row of rows) {
      if (total <= NativeAttachmentCache.scopeQuota) break;
      try {
        fileIo.unlinkSync(directory + '/' + row[0]);
        total -= row[1];
      } catch (_) {}
    }
  }
}
