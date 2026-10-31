/** View-only data source; off-screen rows create no ArkUI components. */
export class NativeListSource<T> implements IDataSource {
  private rows: T[] = [];
  private keys: string[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.rows.length; }
  getData(index: number): T { return this.rows[index]; }
  registerDataChangeListener(listener: DataChangeListener): void { if (!this.listeners.includes(listener)) this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void { this.listeners = this.listeners.filter((item: DataChangeListener) => item !== listener); }
  set(rows: T[], keyOf?: (item: T) => string): void {
    const previous = this.rows;
    const previousKeys = this.keys;
    const key = (item: T): string => keyOf ? keyOf(item) : JSON.stringify(item);
    const occurrences: Map<string, number> = new Map<string, number>();
    const nextKeys = rows.map((item: T): string => {
      const base = key(item);
      const occurrence = occurrences.get(base) || 0;
      occurrences.set(base, occurrence + 1);
      return occurrence === 0 ? base : base + '#' + occurrence;
    });
    // Retain an immutable snapshot: callers frequently append to the same
    // array instance, and a live reference would hide the structural delta.
    this.rows = rows.slice();
    this.keys = nextKeys;
    this.listeners.forEach((listener: DataChangeListener) => {
      if (rows.length === previous.length + 1 &&
        previousKeys.every((value: string, index: number): boolean => value === nextKeys[index])) {
        listener.onDataAdded(rows.length - 1);
        return;
      }
      const stableKeys = rows.length === previous.length &&
        nextKeys.every((value: string, index: number): boolean => value === previousKeys[index]);
      if (stableKeys) {
        // Streaming deltas are appended near the tail. Compare that bounded
        // window instead of serializing a multi-thousand-row transcript on
        // every 40ms paint. Structural changes still take the full reload path.
        const changed: number[] = [];
        const start = Math.max(0, rows.length - 16);
        for (let index = start; index < rows.length; index++) {
          if (JSON.stringify(previous[index]) !== JSON.stringify(rows[index])) changed.push(index);
        }
        if (!changed.length) return;
        if (changed.length <= 4) {
          changed.forEach((index: number): void => { listener.onDataChange(index); });
          return;
        }
      }
      const changed: number[] = [];
      const length = Math.min(previous.length, rows.length);
      for (let index = 0; index < length; index++) {
        if (previousKeys[index] === nextKeys[index] &&
          JSON.stringify(previous[index]) !== JSON.stringify(rows[index])) changed.push(index);
      }
      if (rows.length === previous.length && (rows.length === 0 || key(previous[0]) === key(rows[0])) &&
        changed.length <= 4) {
        changed.forEach((index: number): void => { listener.onDataChange(index); });
        return;
      }
      listener.onDataReloaded();
    });
  }
}
