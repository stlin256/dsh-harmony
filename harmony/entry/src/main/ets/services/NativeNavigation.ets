/** Navigation and menu order are kept outside ArkUI so Back and layout share one source. */
export class NativeNavigationState {
  wide: boolean = false;
  sessions: boolean = true;
  picker: boolean = false;
  create: boolean = false;
  tools: boolean = false;
  menu: boolean = false;
}
export function nativeCanGoBack(state: NativeNavigationState): boolean {
  return state.picker || state.create || state.tools || state.menu || (!state.wide && !state.sessions);
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
