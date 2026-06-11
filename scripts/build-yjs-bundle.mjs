#!/usr/bin/env node
/**
 * Build WKWebView IIFE bundle: global YjsBundle (yjs API for description-editor-bridge.js).
 *
 * Usage (from repo root):
 *   node scripts/build-yjs-bundle.mjs
 *   node scripts/build-yjs-bundle.mjs --check   # exit 1 if bundle stale vs lockfile
 */
import { build } from 'esbuild';
import { createHash } from 'crypto';
import { readFileSync, writeFileSync, existsSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, '..');
const outFile = join(root, 'RecipeScalerNative/Resources/DescriptionEditor/yjs.bundle.js');
const entry = join(__dirname, 'yjs-bundle-entry.js');
const lockFile = join(__dirname, 'package-lock.json');

const checkOnly = process.argv.includes('--check');

function sha256(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

let yjsVersion = '14.0.0-16';
if (existsSync(lockFile)) {
  try {
    const lock = JSON.parse(readFileSync(lockFile, 'utf8'));
    yjsVersion = lock.packages?.['node_modules/yjs']?.version ?? yjsVersion;
  } catch {
    /* ignore */
  }
}

const banner = `/* yjs@${yjsVersion} — rebuild: node scripts/build-yjs-bundle.mjs */\n`;

if (checkOnly && existsSync(outFile)) {
  const current = readFileSync(outFile, 'utf8');
  if (!current.includes(`yjs@${yjsVersion}`)) {
    console.error(`yjs.bundle.js is stale (expected yjs@${yjsVersion}). Run: node scripts/build-yjs-bundle.mjs`);
    process.exit(1);
  }
  console.log(`OK yjs.bundle.js matches yjs@${yjsVersion}`);
  process.exit(0);
}

const result = await build({
  entryPoints: [entry],
  bundle: true,
  format: 'iife',
  globalName: 'YjsBundle',
  platform: 'browser',
  target: ['ios14'],
  minify: true,
  write: false,
  legalComments: 'none',
  logLevel: 'info',
});

const code = banner + result.outputFiles[0].text;
writeFileSync(outFile, code);

const kb = (Buffer.byteLength(code) / 1024).toFixed(1);
console.log(`Wrote ${outFile} (${kb} KB, yjs@${yjsVersion})`);
