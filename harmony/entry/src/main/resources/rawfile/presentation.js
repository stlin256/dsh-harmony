(() => {
  if (window.__pocketPresentation) return;
  window.__pocketPresentation = true;
  let last;
  const sync = () => {
    const settings = location.pathname.startsWith('/pocket/');
    const dark = settings ? document.documentElement.dataset.theme === 'dark' : document.body.hasAttribute('data-ds-dark-theme');
    // Mirror the original theme without changing Harness's theme settings.
    if (!settings) {
      try { localStorage.setItem('pocket-host-dark', String(dark)); } catch {}
    }
    if (last === dark) return;
    last = dark;
    window.dshPocket?.request('presentation', dark ? 'appearanceDark' : 'appearanceLight');
  };
  new MutationObserver(sync).observe(document.body, { attributes: true, attributeFilter: ['data-ds-dark-theme'] });
  new MutationObserver(sync).observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });
  sync();
})();
