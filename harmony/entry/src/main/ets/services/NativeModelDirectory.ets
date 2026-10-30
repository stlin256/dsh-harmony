export class NativeModelSelection { provider: string = ''; model: string = ''; reasoningEffort: string = ''; }
export class NativeModelEffort { id: string = ''; name: string = ''; description: string = ''; }
export class NativeModelReasoning { efforts: NativeModelEffort[] = []; defaultEffort: string = ''; }
export class NativeCatalogModel { id: string = ''; name: string = ''; reasoning: NativeModelReasoning | null = null; }
export class NativeModelProvider { id: string = ''; name: string = ''; models: NativeCatalogModel[] = []; }
export class NativeModelFailure { id: string = ''; name: string = ''; message: string = ''; }
export class NativeModelCatalog { default: NativeModelSelection = new NativeModelSelection(); groups: NativeModelProvider[] = []; failures: NativeModelFailure[] = []; }
class SelectionProjection { next: NativeModelSelection | null = null; }
class ProjectionValues { modelSelection: SelectionProjection | null = null; }
class ProjectionReply { values: ProjectionValues = new ProjectionValues(); }
class SelectionReply { selected: NativeModelSelection = new NativeModelSelection(); }
export class NativeModelDirectoryState {
  catalog: NativeModelCatalog = new NativeModelCatalog();
  selected: NativeModelSelection = new NativeModelSelection();
  generation: number = 0;
}
/** One directory per Session is shared by the composer caption and its selection panel. */
export class NativeModelDirectory {
  private entries: Map<string, NativeModelDirectoryState> = new Map<string, NativeModelDirectoryState>();
  private pending: Map<string, Promise<NativeModelDirectoryState>> = new Map<string, Promise<NativeModelDirectoryState>>();
  private call: (body: string) => Promise<string>;
  private changed: () => void;
  constructor(call: (body: string) => Promise<string>, changed: () => void = (): void => {}) { this.call = call; this.changed = changed; }
  state(id: string): NativeModelDirectoryState {
    let value = this.entries.get(id);
    if (!value) { value = new NativeModelDirectoryState(); this.entries.set(id, value); }
    return value;
  }
  caption(id: string): string {
    const state = this.state(id);
    const provider = state.catalog.groups.find((item: NativeModelProvider) => item.id === state.selected.provider);
    const model = provider?.models.find((item: NativeCatalogModel) => item.id === state.selected.model);
    const effort = state.selected.reasoningEffort || model?.reasoning?.defaultEffort || '';
    const name = model?.reasoning?.efforts.find((item: NativeModelEffort) => item.id === effort)?.name || effort;
    return (model?.name || state.selected.model || '模型') + (name ? ' · ' + name : '');
  }
  async load(id: string): Promise<NativeModelDirectoryState> {
    const active = this.pending.get(id);
    if (active) return active;
    const task = this.read(id).finally((): void => {
      if (this.pending.get(id) === task) this.pending.delete(id);
    });
    this.pending.set(id, task);
    return task;
  }
  private async read(id: string): Promise<NativeModelDirectoryState> {
    const state = this.state(id); const version = ++state.generation;
    const results = await Promise.all([this.call(JSON.stringify({ operation: 'modelCatalog' })), this.call(JSON.stringify({ operation: 'projections', sessionId: id }))]);
    const catalog = JSON.parse(results[0]) as NativeModelCatalog;
    const projection = JSON.parse(results[1]) as ProjectionReply;
    if (version === state.generation) {
      state.catalog = catalog; state.selected = projection.values?.modelSelection?.next || catalog.default; this.changed();
    }
    return state;
  }
  async select(id: string, route: NativeModelSelection): Promise<void> {
    const state = this.state(id); const version = ++state.generation;
    const result = JSON.parse(await this.call(JSON.stringify({ operation: 'selectModel', sessionId: id, provider: route.provider,
      model: route.model, reasoningEffort: route.reasoningEffort || undefined }))) as SelectionReply;
    if (state.generation === version) { state.selected = result.selected; this.changed(); }
  }
  reset(): void { this.entries.forEach((state: NativeModelDirectoryState): void => { state.generation++; }); }
  clear(): void { this.entries.clear(); this.pending.clear(); }
}
