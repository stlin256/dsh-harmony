(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const pending = new Map();
  const titles = { general: '通用', appearance: '外观与动效', about: '关于' };
  for (const tab of document.querySelectorAll('[data-section]')) {
    tab.onclick = () => {
      for (const page of document.querySelectorAll('.settings-page')) page.hidden = page.id !== tab.dataset.section;
      for (const item of document.querySelectorAll('[data-section]')) {
        if (item === tab) item.setAttribute('aria-current', 'page');
        else item.removeAttribute('aria-current');
      }
      $('page-title').textContent = titles[tab.dataset.section];
    };
  }
  try { $('reduce-motion').checked = localStorage.getItem('pocket-reduce-motion') === 'true'; } catch {}
  $('reduce-motion').onchange = () => {
    const reduced = $('reduce-motion').checked;
    document.documentElement.dataset.motion = reduced ? 'reduced' : 'system';
    try { localStorage.setItem('pocket-reduce-motion', String(reduced)); } catch {}
  };
  try {
    const host = localStorage.getItem('pocket-host-dark');
    $('theme-label').textContent = host === 'true' ? '深色' : host === 'false' ? '浅色' : '跟随系统';
  } catch {}

  window.__pocketReply = (id, ok, value) => {
    const item = pending.get(id);
    if (!item) return;
    pending.delete(id); clearTimeout(item.timer);
    ok ? item.resolve(value) : item.reject(Error(value));
  };
  function native(command) {
    if (!window.dshPocket) return Promise.reject(Error('请在 DSH Pocket HarmonyOS 应用中操作'));
    return new Promise((resolve, reject) => {
      const id = crypto.randomUUID();
      const timer = setTimeout(() => { pending.delete(id); reject(Error('系统操作超时，请重试')); }, 60000);
      pending.set(id, { resolve, reject, timer });
      window.dshPocket.request(id, command);
    });
  }
  async function api(path, body, method = 'POST') {
    const response = await fetch('/pocket/api/' + path, { method,
      headers: { 'Content-Type': 'application/json' }, credentials: 'same-origin',
      ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
    if (!response.ok) {
      const value = await response.json().catch(() => ({}));
      throw Error(value.error || '请求失败（' + response.status + '）');
    }
    return response.json();
  }
  const params = new URLSearchParams(location.search);
  let device = localStorage.getItem('pocket-device');
  if (!device) { device = crypto.randomUUID(); localStorage.setItem('pocket-device', device); }
  function action(id, fn, output = 'status') {
    $(id).onclick = async () => {
      $(id).disabled = true;
      $(id).setAttribute('aria-busy', 'true');
      try { await fn(); }
      catch (error) { $(output).textContent = error.message || '操作失败'; }
      finally { $(id).disabled = false; $(id).removeAttribute('aria-busy'); }
    };
  }
  async function passkey(register) {
    if (!window.PublicKeyCredential || !navigator.credentials) throw Error('此系统暂不支持 Passkey');
    const { id, options } = await api('auth/options', { register, ...(register ? { secret: $('secret').value } : {}) });
    $('secret').value = '';
    const response = await (register ? SimpleWebAuthnBrowser.startRegistration({ optionsJSON: options }) : SimpleWebAuthnBrowser.startAuthentication({ optionsJSON: options }));
    await api('auth/verify', { id, response });
    location.replace('/pocket/');
  }
  action('login', () => passkey(false));
  action('register', () => passkey(true));
  action('none', async () => { await api('auth/none', {}); location.replace('/'); });
  action('enable', async () => {
    // A no-auth network still gets a private device-management cookie.
    const state = await api('state', undefined, 'GET');
    if (state.mode === 'none') await api('auth/none', {});
    const token = await native('enablePush');
    await api('device', { id: device, token });
    $('push-status').textContent = '通知已开启。系统权限或 Push token 更新后请再次点击开启。';
  }, 'push-status');
  action('disable', async () => {
    await api('device', { id: device }, 'DELETE');
    await native('disablePush');
    $('push-status').textContent = '通知已关闭';
  }, 'push-status');
  async function logout() {
    await api('logout', {});
    if (window.dshPocket) await native('clearSession');
    else location.replace('/pocket/');
  }
  action('logout', logout, 'account-status');
  async function initialize() {
    if (params.get('logout') === '1') { await logout(); return; }
    const state = await api('state', undefined, 'GET');
    $('heading').textContent = state.authenticated ? '工作空间已连接' : '登录工作空间';
    $('status').textContent = state.authenticated ? '已准备就绪，可以继续你的任务。' : state.registered ? '使用你的 Passkey 安全登录。' : '首次连接：输入管理员提供的配对密钥，创建 Passkey。';
    $('workspace').hidden = !state.authenticated;
    $('notifications').hidden = !state.authenticated;
    $('account').hidden = !state.authenticated;
    $('enable').disabled = !state.pushConfigured;
    if (!state.pushConfigured) $('push-status').textContent = '服务器尚未配置 Huawei Push 服务账号';
    if (!state.authenticated && state.mode === 'passkey') {
      $('login').hidden = !state.registered;
      $('register').hidden = state.registered;
      $('secret-label').hidden = state.registered;
      $('compat').hidden = !!window.PublicKeyCredential;
    }
    $('none').hidden = state.mode !== 'none';
    if (params.get('mode') === 'none' && state.mode !== 'none') $('status').textContent = '此服务要求 Passkey 登录，客户端选择不能更改服务端策略。';
    const session = params.get('session');
    if (state.authenticated && session && /^[A-Za-z0-9_-]{1,160}$/.test(session)) {
      $('session').hidden = false; $('session-id').textContent = session;
    }
  }
  initialize().catch(error => { $('status').textContent = error.message; });
})();
