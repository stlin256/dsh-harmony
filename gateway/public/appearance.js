// Apply before stylesheet paint. Only presentation preferences are stored here.
(() => {
  const root = document.documentElement;
  const system = matchMedia('(prefers-color-scheme: dark)');
  const apply = () => {
    let theme = null;
    try {
      theme = localStorage.getItem('pocket-host-dark');
      root.dataset.motion = localStorage.getItem('pocket-reduce-motion') === 'true' ? 'reduced' : 'system';
    } catch { /* Storage-disabled browsers keep system appearance. */ }
    root.dataset.theme = theme === 'true' || (theme !== 'false' && system.matches) ? 'dark' : 'light';
  };
  apply();
  system.addEventListener('change', apply);
  window.addEventListener('storage', apply);
})();
