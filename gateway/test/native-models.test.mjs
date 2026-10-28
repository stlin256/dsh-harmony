// Exercises service logic under kit mocks. This is not an ArkTS/Hvigor build.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import ts from 'typescript';

const services = new URL('../../harmony/entry/src/main/ets/services/', import.meta.url);
function load(name, kits, globals = {}) {
  const source = readFileSync(new URL(name + '.ets', services), 'utf8');
  const output = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS } });
  const module = { exports: {} };
  vm.runInNewContext(output.outputText, { module, exports: module.exports, require: id => {
    if (!(id in kits)) throw Error('Unexpected dependency: ' + id);
    return kits[id];
  }, ...globals });
  return module.exports;
}
function storage() {
  const disk = new Map();
  const preferences = {
    removePreferencesFromCacheSync() {},
    getPreferencesSync(_ctx, { name }) {
      if (!disk.has(name)) disk.set(name, new Map());
      const file = disk.get(name);
      return { getSync: (key, fallback) => structuredClone(file.has(key) ? file.get(key) : fallback),
        putSync: (key, value) => file.set(key, structuredClone(value)), flushSync() {} };
    }
  };
  return { disk, preferences };
}
const context = { getApplicationContext() { return this; } };

test('widget privacy defaults, cross-process restoration, expiry and logout serialization', async () => {
  const { preferences, disk } = storage();
  const deliveries = [];
  let block;
  let now = Date.now();
  class Clock extends Date { static now() { return now; } }
  const kits = { '@kit.AbilityKit': {}, '@kit.ArkData': { preferences }, '@kit.FormKit': {
    formBindingData: { createFormBindingData: data => ({ data }) }, formProvider: {
      async updateForm(id, value) { if (block) await block; deliveries.push({ id, value }); }
    }
  } };
  const { WidgetStore, OverviewSnapshot } = load('WidgetStore', kits, { Date: Clock });
  WidgetStore.register(context, '123');
  WidgetStore.register(context, '123');
  const snapshot = Object.assign(new OverviewSnapshot(), { running: 2, waiting: 1, completed: 3, failed: 0, observedAt: now, generatedAt: now });
  await WidgetStore.update(context, snapshot);
  assert.equal(WidgetStore.data(context).showCounts, false);
  assert.equal(disk.get('pocket-widget-snapshot').get('snapshot'), '');
  assert.equal(deliveries.length, 1, 'duplicate form instance IDs must not duplicate delivery');
  await WidgetStore.setDetails(context, true);
  await WidgetStore.update(context, snapshot);
  assert.equal(WidgetStore.data(context).showCounts, true);
  assert.equal(WidgetStore.data(context).running, '2');
  const restarted = load('WidgetStore', kits, { Date: Clock });
  assert.equal(restarted.WidgetStore.data(context).waiting, '1');
  now += 16 * 60000;
  assert.equal(WidgetStore.data(context).showCounts, false);
  assert.match(WidgetStore.data(context).detail, /过期/);
  let release;
  block = new Promise(resolve => { release = resolve; });
  const updating = WidgetStore.update(context, snapshot);
  const clearing = WidgetStore.clear(context);
  release(); block = null;
  await Promise.all([updating, clearing]);
  assert.equal(WidgetStore.data(context).headline, '连接工作空间');
  assert.equal(deliveries.at(-1).value.data.showCounts, false);
  assert.equal(disk.get('pocket-widget-snapshot').get('snapshot'), '');
  WidgetStore.remove(context, '123');
  const before = deliveries.length;
  await WidgetStore.update(context, snapshot);
  assert.equal(deliveries.length, before, 'removed form must not receive updates');
});

test('system material guards old runtimes and respects opacity, motion and power policies', () => {
  const { preferences } = storage();
  const state = new Map();
  const AppStorage = { get: key => state.get(key), setOrCreate: (key, value) => state.set(key, value) };
  const deviceInfo = { sdkApiVersion: 23 };
  const uiMaterial = { getMaterialInfo: () => ({ state: 0 }), MaterialState: { DISABLE: 2 }, Material: { empty: { disabled: true } },
    ImmersiveStyle: { THIN: 1 }, ImmersiveMaterial: class { constructor(options) {
      assert.ok(deviceInfo.sdkApiVersion >= 26, 'API-26 constructor reached on old device'); this.options = options;
    } } };
  const power = { getPowerMode: () => 600, DevicePowerMode: { MODE_NORMAL: 600, MODE_PERFORMANCE: 602 } };
  const kits = { '@kit.AbilityKit': {}, '@kit.ArkData': { preferences }, '@kit.BasicServicesKit': { deviceInfo, power },
    '@kit.AccessibilityKit': { accessibility: { isAnimationReduceEnabledSync: () => false } }, '@kit.ArkUI': { uiMaterial } };
  const { NativeExperience, ChromeMaterialModifier } = load('NativeExperience', kits, { AppStorage, canIUse: () => true, BarStyle: { STANDARD: 0 }, Color: { White: '#fff' } });
  NativeExperience.refresh(context);
  assert.equal(NativeExperience.materialsEnabled(), false);
  assert.equal(NativeExperience.titleOptions(false, 0).systemMaterial, undefined);
  let applied;
  new ChromeMaterialModifier(0).applyNormalAttribute({ systemMaterial: value => { applied = value; } });
  assert.equal(applied, undefined);
  deviceInfo.sdkApiVersion = 26;
  assert.equal(NativeExperience.materialsEnabled(), true);
  new ChromeMaterialModifier(1).applyNormalAttribute({ systemMaterial: value => { applied = value; } });
  assert.equal(applied.options.interactive, true);
  state.set('nativeSystemReduceMotion', true);
  new ChromeMaterialModifier(2).applyNormalAttribute({ systemMaterial: value => { applied = value; } });
  assert.equal(applied.options.interactive, false);
  assert.equal(applied.options.lightEffect, null);
  NativeExperience.setPreference(context, 'reduceTransparency', true);
  assert.equal(NativeExperience.materialsEnabled(), false);
  assert.equal(NativeExperience.titleOptions(false, 0).systemMaterial.disabled, true);
  NativeExperience.setPreference(context, 'reduceTransparency', false);
  state.set('nativePowerSaving', true);
  assert.equal(NativeExperience.materialsEnabled(), false);
  state.set('nativePowerSaving', false); state.set('nativeAppActive', false);
  assert.equal(NativeExperience.materialsEnabled(), false);
});

test('form metadata resolves actual static card pages and resources', () => {
  const base = new URL('../../harmony/entry/src/main/', import.meta.url);
  const manifest = JSON.parse(readFileSync(new URL('module.json5', base), 'utf8'));
  const forms = JSON.parse(readFileSync(new URL('resources/base/profile/form_config.json', base), 'utf8')).forms;
  assert.equal(manifest.module.extensionAbilities[0].type, 'form');
  assert.equal(manifest.module.abilities[0].launchType, 'singleton');
  assert.equal(forms.filter(form => form.isDefault).length, 1);
  assert.deepEqual(forms.map(form => form.defaultDimension), ['2*2', '2*4']);
  for (const form of forms) {
    assert.ok(form.supportDimensions.includes(form.defaultDimension));
    assert.equal(form.isDynamic, false);
    assert.ok(existsSync(fileURLToPath(new URL(form.src, base))));
    const source = readFileSync(new URL(form.src, base), 'utf8');
    assert.match(source, /FormLink/);
    assert.doesNotMatch(source, /fetch\(|Web\(|INTERNET|cookie|serverOrigin/);
  }
});
