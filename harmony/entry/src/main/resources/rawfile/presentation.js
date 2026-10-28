(() => {
  if (window.__pocketPresentation) return;
  window.__pocketPresentation = true;
  let last;
  let timer;
  let syncing = false;
  let activeRequest;
  let refreshAgain = false;
  let hostActive = true;
  const request = (command, value = '') => window.dshPocket?.request('presentation_' + crypto.randomUUID(), command, value);
  const syncTheme = () => {
    const settings = location.pathname.startsWith('/pocket/');
    const dark = settings ? document.documentElement.dataset.theme === 'dark' : document.body.hasAttribute('data-ds-dark-theme');
    if (!settings) {
      try { localStorage.setItem('pocket-host-dark', String(dark)); } catch {}
    }
    if (last === dark) return;
    last = dark;
    request(dark ? 'appearanceDark' : 'appearanceLight');
  };
  // Local cards receive only authenticated aggregate snapshots, never cookies,
  // server addresses, session IDs, conversation text or upstream credentials.
  window.__pocketSyncOverview = async () => {
    clearTimeout(timer);
    if (syncing || !hostActive || document.hidden) return;
    syncing = true;
    const controller = new AbortController();
    activeRequest = controller;
    const cutoff = setTimeout(() => controller.abort(), 8000);
    try {
      const response = await fetch('/pocket/api/overview', { credentials: 'same-origin', cache: 'no-store', signal: controller.signal });
      if (!hostActive || document.hidden) return;
      if (response.status === 401) request('widgetDisconnected');
      else if (response.ok) {
        const data = await response.json();
        if (!hostActive || document.hidden) return;
        request('widgetSnapshot', JSON.stringify({ running: data.running, waiting: data.waiting, completed: data.completed,
          failed: data.failed, unknown: data.unknown, observedAt: data.observedAt, generatedAt: data.generatedAt }));
      }
    } catch { /* Keep the explicitly dated cached snapshot while offline. */ }
    finally {
      clearTimeout(cutoff);
      activeRequest = undefined;
      syncing = false;
      if (hostActive && !document.hidden) timer = setTimeout(window.__pocketSyncOverview, refreshAgain ? 0 : 60000);
      refreshAgain = false;
    }
  };
  window.__pocketSuspendOverview = () => { hostActive = false; clearTimeout(timer); activeRequest?.abort(); };
  window.__pocketResumeOverview = () => { hostActive = true;
    if (syncing) refreshAgain = true;
    else void window.__pocketSyncOverview(); };
  document.addEventListener('visibilitychange', () => {
    clearTimeout(timer);
    if (document.hidden) activeRequest?.abort();
    if (!document.hidden && hostActive) void window.__pocketSyncOverview();
  });
  new MutationObserver(syncTheme).observe(document.body, { attributes: true, attributeFilter: ['data-ds-dark-theme'] });
  new MutationObserver(syncTheme).observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });
  syncTheme();
  void window.__pocketSyncOverview();
})();
