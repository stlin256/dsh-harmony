const HISTORY_RETRY_DELAYS: number[] = [600, 1200, 2400, 4800, 8000];

/** Bounded exponential backoff for an automatic history-page retry. */
export class NativeHistoryRetryPolicy {
  private failures: number = 0;

  failureCount(): number {
    return this.failures;
  }

  nextDelay(): number {
    const index = Math.min(this.failures, HISTORY_RETRY_DELAYS.length - 1);
    this.failures++;
    return HISTORY_RETRY_DELAYS[index];
  }

  succeed(): void {
    this.failures = 0;
  }

  reset(): void {
    this.failures = 0;
  }
}

/**
 * A page with hasMore=true only counts as progress when it moves the cursor or
 * adds at least one visible row. This prevents a broken Host response from
 * causing a tight retry loop.
 */
export function nativeHistoryPageAdvanced(beforeSeq: number, nextBeforeSeq: number,
  previousRowCount: number, nextRowCount: number, hasMore: boolean): boolean {
  if (!hasMore) return true;
  return nextBeforeSeq !== beforeSeq || nextRowCount > previousRowCount;
}
