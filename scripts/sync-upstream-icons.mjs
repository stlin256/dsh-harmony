// Regenerate bundled DSH glyphs from the reviewed upstream revision, never from a live URL.
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { mkdirSync, writeFileSync } from 'node:fs';
import vm from 'node:vm';
const require = createRequire(new URL('../gateway/package.json', import.meta.url));
const ts = require('typescript');
const revision = 'f3803c96974ad4a94195fb97e5c637e9c2a3afe3';
const clone = process.argv[2];
if (!clone) throw Error('Usage: node scripts/sync-upstream-icons.mjs <official-clone>');
const source = execFileSync('git', ['-C', clone, 'show', revision + ':packages/client/ui-primitives/src/icons/artwork.ts'], { encoding: 'utf8', maxBuffer: 4 * 1024 * 1024 });
const module = { exports: {} };
vm.runInNewContext(ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText, { module, exports: module.exports });
const glyphs = ['think-outline','browse-outline','search-outline','edit-outline','api-outline','code-outline','globe-outline','agent-preset-outline','plan-outline','question-outline','sparkle',
  'pin-outline','pin-fill','branch-outline','archive-outline','download-outline','close-outline','light-outline','dark-outline','followsystem-outline','personalization-outline'];
const root = new URL('../harmony/entry/src/main/resources/rawfile/dsh-icons/', import.meta.url);
mkdirSync(root, { recursive: true });
for (const name of glyphs) {
  const artwork = module.exports.ICON_ARTWORK[name];
  if (!artwork) { console.log('Absent upstream glyph: ' + name); continue; }
  writeFileSync(new URL(name + '.svg', root), artwork.svg(1).replaceAll('currentColor', '#000000') + '\n');
}
console.log('Bundled upstream glyphs at ' + revision.slice(0, 7));
