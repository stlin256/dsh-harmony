export class NativeFileWindowMetadata {
  version: string = '';
  bytes: number = -1;
  offset: number = 0;
  eof: boolean = false;
  length: number = 0;
}

/**
 * Derive window completion from the stat response when a platform HTTP client
 * does not expose the custom metadata header. This keeps byte transport
 * independent from optional response headers while preserving exact EOF
 * behavior for files that end on a window boundary.
 */
export function nativeFileWindowMetadata(version: string, bytes: number, offset: number,
  observedLength: number, requestedLength: number): NativeFileWindowMetadata {
  const value = new NativeFileWindowMetadata();
  value.version = version;
  value.bytes = bytes;
  value.offset = offset;
  value.length = observedLength;
  value.eof = bytes >= 0 ? offset + observedLength >= bytes : observedLength < requestedLength;
  return value;
}
