import { NativeHarnessClient } from '../services/NativeHarnessClient';
import { NativeSession, NativeWorkspaceItem, NativeWorkspaceSnapshot } from '../services/NativeSessionModel';
import { DSHIcon } from './DSHIcon';
import { NativeExperience } from '../services/NativeExperience';

class WorkspaceCreated { workspace: NativeWorkspaceItem = new NativeWorkspaceItem(); }

@Component
export struct NativeWorkspacePicker {
  client: NativeHarnessClient = new NativeHarnessClient('');
  @Prop snapshot: NativeWorkspaceSnapshot = new NativeWorkspaceSnapshot();
  @Prop sessions: NativeSession[] = [];
  @Prop selectedId: string = '';
  onClose: () => void = (): void => {};
  onSelect: (id: string) => void = (): void => {};
  onChanged: (value: NativeWorkspaceSnapshot) => void = (): void => {};
  @StorageLink('nativeDark') private dark: boolean = false;
  @State private creating: boolean = false;
  @State private archived: boolean = false;
  @State private path: string = '';
  @State private editingId: string = '';
  @State private title: string = '';
  @State private busy: boolean = false;
  @State private error: string = '';
  private async command(body: string): Promise<void> {
    if (this.busy) return;
    this.busy = true; this.error = '';
    try {
      const value = await this.client.operation(body);
      this.onChanged(await this.client.workspaces());
      if (this.creating) { this.creating = false; this.onSelect((JSON.parse(value) as WorkspaceCreated).workspace.workspaceId); }
      this.editingId = '';
    } catch (_) { this.error = '操作未确认，请刷新'; }
    finally { this.busy = false; }
  }
  @Builder
  private row(title: string, detail: string, selected: boolean, click: () => void) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 8 }) {
        DSHIcon({ glyph: 'browse-outline', color: this.dark ? '#93969B' : '#8A8D91', glyphSize: 16 })
        Column({ space: 3 }) {
          Text(title).fontSize(14).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor(this.dark ? '#F9FAFB' : '#17181B')
          if (detail) { Text(detail).fontSize(11).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor(this.dark ? '#93969B' : '#8A8D91') }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (selected) { DSHIcon({ glyph: 'check-outline', color: this.dark ? '#8AB4FF' : '#3964FE' }) }
      }.width('100%')
    }.width('100%').constraintSize({ minHeight: 44 }).padding(8).borderRadius(9)
      .backgroundColor(selected ? this.dark ? '#2C2C2E' : '#EBEEF2' : Color.Transparent).onClick(click)
  }
  build() {
    Column({ space: 10 }) {
      Row({ space: 6 }) {
        Button({ type: ButtonType.Normal }) {
          DSHIcon({ glyph: 'chevron-left-outline', color: this.dark ? '#F9FAFB' : '#17181B' })
        }.width(36).height(36).backgroundColor(Color.Transparent)
          .onClick(() => { if (this.creating || this.archived) { this.creating = false; this.archived = false; } else this.onClose(); })
        Text(this.creating ? '添加工作区' : this.archived ? '已归档会话' : '工作区').fontSize(18).fontWeight(FontWeight.Medium).layoutWeight(1)
          .fontColor(this.dark ? '#F9FAFB' : '#17181B')
      }.width('100%')
      Scroll() {
        Column({ space: 5 }) {
          if (this.creating) {
            TextInput({ text: this.path, placeholder: '服务器上的目录路径' }).height(42).fontSize(14)
              .onChange((value: string) => { this.path = value; })
            Button('添加', { type: ButtonType.Normal }).height(40).width('100%').borderRadius(10)
              .backgroundColor(this.dark ? '#679EFE' : '#3964FE').fontColor('#FFFFFF').enabled(!this.busy && this.path.trim().length > 0)
              .onClick(() => { this.command(JSON.stringify({ operation: 'workspaceCreate', path: this.path.trim() })); })
          } else if (this.archived) {
            ForEach(this.snapshot.archivedSessionIds, (id: string) => {
              Row({ space: 8 }) {
                Text(this.sessions.find((row: NativeSession) => row.id === id)?.title || '未命名会话')
                  .fontSize(13).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Button('恢复', { type: ButtonType.Normal }).height(34).fontSize(12).enabled(!this.busy)
                  .onClick(() => { this.command(JSON.stringify({ operation: 'unarchive', sessionId: id })); })
              }.width('100%').padding(6)
            }, (id: string) => id)
            if (!this.snapshot.archivedSessionIds.length) { Text('没有已归档会话').fontSize(13) }
          } else {
            this.row('全部会话', '', !this.selectedId, () => { this.onSelect(''); })
            ForEach(this.snapshot.items, (workspace: NativeWorkspaceItem) => {
              Row({ space: 4 }) {
                Column() { this.row(workspace.title, workspace.path, this.selectedId === workspace.workspaceId, () => { this.onSelect(workspace.workspaceId); }) }.layoutWeight(1)
                Button({ type: ButtonType.Normal }) {
                  DSHIcon({ glyph: 'ellipsis-outline', color: this.dark ? '#93969B' : '#8A8D91' })
                }.width(34).height(36).backgroundColor(Color.Transparent)
                  .onClick(() => { this.editingId = workspace.workspaceId; this.title = workspace.title; })
              }.width('100%')
              if (this.editingId === workspace.workspaceId) {
                Row({ space: 6 }) {
                  TextInput({ text: this.title }).fontSize(13).height(38).layoutWeight(1).onChange((value: string) => { this.title = value; })
                  Button('保存').height(34).fontSize(12).enabled(!this.busy && this.title.trim().length > 0)
                    .onClick(() => { this.command(JSON.stringify({ operation: 'workspaceRename', workspaceId: this.editingId, title: this.title.trim() })); })
                }.padding(6)
              }
            }, (workspace: NativeWorkspaceItem) => workspace.workspaceId)
            if (this.snapshot.available) {
              Divider().color(this.dark ? '#353538' : '#E8E9EC').margin({ top: 8, bottom: 8 })
              this.row('添加工作区', '', false, () => { this.creating = true; })
              this.row('已归档会话', '', false, () => { this.archived = true; })
            }
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%').align(Alignment.Top)
      if (this.busy) { LoadingProgress().width(20).height(20) }
      if (this.error) { Text(this.error).fontSize(12).fontColor('#D55E5E') }
    }.padding(12).width('100%').height('100%').backgroundColor(this.dark ? '#151517' : '#FFFFFF')
      .foregroundColor(this.dark ? '#F9FAFB' : '#17181B')
      .transition(NativeExperience.reducedMotion() ? TransitionEffect.IDENTITY :
        TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: 8 })))
  }
}
