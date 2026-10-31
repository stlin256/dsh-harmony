export class NativeLaunchPhase {
  static readonly booting: string = 'booting';
  static readonly intro: string = 'intro';
  static readonly guide: string = 'guide';
  static readonly install: string = 'install';
  static readonly login: string = 'login';
  static readonly restoring: string = 'restoring';
  static readonly error: string = 'error';
  static readonly entering: string = 'entering';
  static readonly hidden: string = 'hidden';
}

/**
 * Pure launch decisions shared by cold start, logout and error recovery.
 * Network work stays in Index; this class only defines which surface may be
 * visible and which failures need user credentials.
 */
export class NativeLaunchFlow {
  static afterPreferences(hasOrigin: boolean, onboardingSeen: boolean): string {
    if (!hasOrigin || !onboardingSeen) return NativeLaunchPhase.intro;
    return NativeLaunchPhase.restoring;
  }

  static needsLogin(message: string): boolean {
    const value = message.trim();
    return value === '请输入访问密钥' ||
      value === '此服务需要 Passkey 登录' ||
      value === '登录失败，请检查访问密钥' ||
      value.startsWith('登录失败') ||
      value.startsWith('上次登录');
  }

  static safeMessage(error: Error | null, fallback: string): string {
    const value = error?.message?.trim() || fallback;
    return value.slice(0, 500);
  }
}
