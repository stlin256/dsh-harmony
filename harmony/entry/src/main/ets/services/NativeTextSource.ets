/** Fixed-size rendering windows, with no content cap and no copy per off-screen row. */
export class NativeTextSource implements IDataSource {
  private value: string = '';
  private listeners: DataChangeListener[] = [];
  private readonly window: number = 4096;
  totalCount(): number { return Math.ceil(this.value.length / this.window); }
  private boundary(index: number): number {
    const offset = Math.min(this.value.length, index * this.window);
    const code = this.value.charCodeAt(offset);
    return code >= 0xDC00 && code <= 0xDFFF && offset > 0 ? offset - 1 : offset;
  }
  getData(index: number): string { return this.value.slice(this.boundary(index), this.boundary(index + 1)); }
  registerDataChangeListener(listener: DataChangeListener): void { if (!this.listeners.includes(listener)) this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void { this.listeners = this.listeners.filter((item: DataChangeListener) => item !== listener); }
  set(value: string): void {
    this.value = value;
    this.listeners.forEach((listener: DataChangeListener) => { listener.onDataReloaded(); });
  }
}
