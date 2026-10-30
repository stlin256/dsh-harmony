/** Uses the public workspace service; no DOM traversal or private store access. */
export const inject = ['uiWorkspace'];
export function consumeSession(url) {
  const id = url.searchParams.get('dshHarmonySession');
  return typeof id === 'string' && /^[A-Za-z0-9_-]{1,160}$/.test(id) ? id : '';
}
export function apply(ctx) {
  const url = new URL(window.location.href);
  const id = consumeSession(url);
  if (!id) return;
  const handoff = () => {
    try {
      ctx.uiWorkspace.openSession(id);
      url.searchParams.delete('dshHarmonySession');
      window.history.replaceState(window.history.state, '', url.pathname + url.search + url.hash);
    } catch (error) {
      globalThis.console?.warn?.('@dsh-harmony/navigation: session handoff failed', error);
    }
  };
  const schedule = () => {
    const timer = setTimeout(handoff, 0);
    return () => clearTimeout(timer);
  };
  if (typeof ctx.effect === 'function') {
    ctx.effect(schedule, 'dsh-harmony: session handoff');
  } else {
    schedule();
  }
}
