/** View-only data source; off-screen rows create no ArkUI components. */
export class NativeListSource<T> implements IDataSource {
  private rows: T[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.rows.length; }
  getData(index: number): T { return this.rows[index]; }
  registerDataChangeListener(listener: DataChangeListener): void { if (!this.listeners.includes(listener)) this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void { this.listeners = this.listeners.filter((item: DataChangeListener) => item !== listener); }
  set(rows: T[]): void {
    this.rows = rows;
    this.listeners.forEach((listener: DataChangeListener) => { listener.onDataReloaded(); });
  }
}
