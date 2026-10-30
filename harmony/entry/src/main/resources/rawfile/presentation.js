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
  const installSettingsButton = () => {
    if (!document.body || location.pathname.startsWith('/pocket/')) return;
    if (document.querySelector('[data-dsh-harmony-settings]')) return;
    // Reuse the upstream sidebar settings row so this stays aligned with its
    // navigation, spacing and theme. The original web settings remain intact.
    const dividers = [...document.querySelectorAll('.nav-divider')];
    const footer = dividers.map(node => node.parentElement).find(node =>
      node?.querySelector('button svg.lucide-settings'));
    const original = footer?.querySelector('button svg.lucide-settings')?.closest('button');
    const originalRow = original?.parentElement;
    if (!footer || !original || !originalRow) return;

    const row = originalRow.cloneNode(true);
    row.setAttribute('data-dsh-harmony-settings', '');
    // The upstream desktop entry is hidden below its md breakpoint. Harmony
    // needs the same control in the compact/mobile sidebar as well.
    row.className = 'px-2 py-1.5';
    const button = row.querySelector('button');
    if (!button) return;
    button.className = 'flex w-full items-center gap-2 rounded-lg px-2.5 py-1.5 text-muted-foreground transition-colors hover:bg-accent/60 hover:text-foreground';
    button.title = '应用设置';
    button.setAttribute('aria-label', '应用设置');
    const label = button.querySelector('span');
    if (label) label.textContent = '应用设置';
    // Keep the upstream flat Lucide gear and reset its visual state.
    const icon = button.querySelector('svg');
    if (icon) {
      icon.classList.remove('text-primary', 'text-blue-500');
      icon.setAttribute('aria-hidden', 'true');
    }
    button.addEventListener('click', event => {
      event.preventDefault(); event.stopPropagation();
      request('openSettings');
    });
    originalRow.after(row);
  };
  const openRequestedRoute = () => {
    const url = new URL(location.href);
    const route = url.searchParams.get('dshHarmonyRoute');
    if (!['plugins', 'automation', 'more'].includes(route)) return;
    url.searchParams.delete('dshHarmonyRoute');
    history.replaceState(history.state, '', url.pathname + url.search + url.hash);
    if (route === 'more') {
      window.__dshHarmonyRouteReady = true;
      return;
    }
    const labels = route === 'plugins' ? ['插件', 'Plugins'] : ['自动化任务', 'Automation tasks'];
    let attempts = 0;
    const select = () => {
      const navigation = document.querySelector('nav[aria-label="全局面板"], nav[aria-label="Global panels"]');
      const buttons = navigation ? [...navigation.querySelectorAll('button')] : [];
      const target = buttons.find(button => labels.includes((button.textContent || '').trim()));
      if (target) {
        target.click();
        window.__dshHarmonyRouteReady = true;
        return;
      }
      attempts++;
      if (attempts < 40) setTimeout(select, 150);
      else window.__dshHarmonyRouteUnavailable = route;
    };
    setTimeout(select, 0);
  };
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
  new MutationObserver(installSettingsButton).observe(document.body, { childList: true, subtree: true });
  installSettingsButton();
  openRequestedRoute();
  syncTheme();
  void window.__pocketSyncOverview();
})();
