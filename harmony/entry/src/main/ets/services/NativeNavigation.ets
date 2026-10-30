/** Navigation and menu order are kept outside ArkUI so Back and layout share one source. */
export class NativeNavigationState {
  wide: boolean = false;
  drawerOpen: boolean = false;
  drawerPage: string = 'primary';
  picker: boolean = false;
  create: boolean = false;
  tools: boolean = false;
  menu: boolean = false;
  imagePreview: boolean = false;
  filePreview: boolean = false;
}
export function nativeCanGoBack(state: NativeNavigationState): boolean {
  return state.drawerOpen === true || state.picker === true || state.create === true ||
    state.tools === true || state.menu === true || state.imagePreview === true ||
    state.filePreview === true;
}
export class NativeMenuItem {
  id: string = '';
  title: string = '';
  icon: string = '';
  danger: boolean = false;
  disabled: boolean = false;
  separator: boolean = false;
}
export function nativeSessionMenu(pinned: boolean, archived: boolean = false): NativeMenuItem[] {
  const rows: NativeMenuItem[] = [];
  if (!archived) rows.push({ id: pinned ? 'unpin' : 'pin', title: pinned ? '取消置顶' : '置顶', icon: pinned ? 'pin-fill' : 'pin-outline', danger: false, disabled: false, separator: false });
  rows.push({ id: 'rename', title: '重命名', icon: 'edit-outline', danger: false, disabled: false, separator: false });
  rows.push({ id: 'fork', title: '创建分支', icon: 'branch-outline', danger: false, disabled: false, separator: false });
  rows.push({ id: archived ? 'unarchive' : 'archive', title: archived ? '恢复会话' : '归档会话', icon: 'archive-outline', danger: false, disabled: false, separator: false });
  rows.push({ id: 'copyId', title: '复制会话 ID', icon: 'copy-outline', danger: false, disabled: false, separator: true });
  return rows;
}

/** The more menu is complete before asynchronous capability discovery finishes. */
export function nativeUtilityMenu(known: boolean, copyMarkdown: boolean, downloadLog: boolean,
  copying: boolean, downloading: boolean): NativeMenuItem[] {
  const rows: NativeMenuItem[] = [
    { id: 'files', title: '文件浏览', icon: 'browse-outline',
      danger: false, disabled: false, separator: false }
  ];
  if (!known || copyMarkdown) rows.push({ id: 'copy', title: '复制 Markdown', icon: 'copy-outline',
    danger: false, disabled: copying, separator: false });
  if (!known || downloadLog) rows.push({ id: 'download', title: '下载日志', icon: 'download-outline',
    danger: false, disabled: downloading, separator: false });
  return rows;
}

/** Upstream increments an existing ASCII/full-width numeric suffix, preserving the parentheses. */
export function nativeForkTitle(title: string): string {
  const ascii = /^(.*?)\((\d+)\)$/.exec(title);
  const wide = /^(.*?)（(\d+)）$/.exec(title);
  const match = ascii || wide;
  if (!match) return title + ' (1)';
  const digits = match[2].replace(/^0+(?=\d)/, '').split('');
  let carry = 1;
  for (let index = digits.length - 1; index >= 0 && carry; index--) {
    const value = Number(digits[index]) + carry; digits[index] = String(value % 10); carry = value >= 10 ? 1 : 0;
  }
  if (carry) digits.unshift('1');
  return match[1] + (ascii ? '(' : '（') + digits.join('') + (ascii ? ')' : '）');
}
