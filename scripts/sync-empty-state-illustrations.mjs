#!/usr/bin/env node
/**
 * Sync empty-state illustration JPGs from recipe-scaler-web into Assets.xcassets.
 *
 * Usage:
 *   node scripts/sync-empty-state-illustrations.mjs
 *   node scripts/sync-empty-state-illustrations.mjs --check
 *   WEB_ROOT=/path/to/recipe-scaler-web node scripts/sync-empty-state-illustrations.mjs
 */

import { execSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const NATIVE_ROOT = path.resolve(__dirname, '..');
const WEB_ROOT = process.env.WEB_ROOT
  ? path.resolve(process.env.WEB_ROOT)
  : path.resolve(NATIVE_ROOT, '../recipe-scaler-web');

const REGISTRY_PATH = path.join(
  WEB_ROOT,
  'recipe-scaler/src/data/empty-state-illustrations/registry.json',
);
const WEB_IMAGES_DIR = path.join(
  WEB_ROOT,
  'recipe-scaler/public/assets/illustrations/empty-states',
);

const ASSETS_DIR = path.join(NATIVE_ROOT, 'RecipeScalerNative/Assets.xcassets');

/** Web registry id → Xcode imageset folder name (Image asset name). */
const WEB_ID_TO_ASSET = {
  'recipe-notebook-empty': 'empty-state-recipe-notebook',
  'shopping-basket-empty': 'empty-state-shopping-basket-empty',
  'shopping-basket-full': 'empty-state-shopping-basket-full',
};

/** 192 pt @3x */
const PIXEL_SIZE = 576;
const CHECK_ONLY = process.argv.includes('--check');
const MANIFEST_PATH = path.join(ASSETS_DIR, 'EmptyStateIllustrations.manifest.json');

function readReadyEntries() {
  const raw = fs.readFileSync(REGISTRY_PATH, 'utf8');
  const registry = JSON.parse(raw);
  const ready = (registry.entries ?? []).filter((e) => e.status === 'ready');
  for (const e of ready) {
    if (!WEB_ID_TO_ASSET[e.id]) {
      throw new Error(`No asset mapping for registry id: ${e.id}`);
    }
  }
  ready.sort((a, b) => a.id.localeCompare(b.id));
  return ready;
}

function contentsJson(filename) {
  return {
    images: [
      { filename, idiom: 'universal', scale: '1x' },
      { filename, idiom: 'universal', scale: '2x' },
      { filename, idiom: 'universal', scale: '3x' },
    ],
    info: { author: 'xcode', version: 1 },
  };
}

function resizeToSquare(src, dest) {
  const tmp = `${dest}.tmp.jpg`;
  fs.copyFileSync(src, tmp);
  execSync(`sips -z ${PIXEL_SIZE} ${PIXEL_SIZE} "${tmp}" --out "${dest}"`, {
    stdio: 'pipe',
  });
  fs.unlinkSync(tmp);
}

function fileSha256(filePath) {
  const data = fs.readFileSync(filePath);
  return crypto.createHash('sha256').update(data).digest('hex');
}

function syncOne(webId, assetName) {
  const src = path.join(WEB_IMAGES_DIR, `${webId}.jpg`);
  if (!fs.existsSync(src)) {
    return { ok: false, error: `missing source ${src}` };
  }
  const imagesetDir = path.join(ASSETS_DIR, `${assetName}.imageset`);
  const filename = `${assetName}.jpg`;
  const dest = path.join(imagesetDir, filename);
  if (!CHECK_ONLY) {
    fs.mkdirSync(imagesetDir, { recursive: true });
    resizeToSquare(src, dest);
    fs.writeFileSync(
      path.join(imagesetDir, 'Contents.json'),
      JSON.stringify(contentsJson(filename), null, 2) + '\n',
      'utf8',
    );
  } else if (!fs.existsSync(dest)) {
    return { ok: false, error: `missing ${dest}` };
  }
  return { ok: true, hash: fileSha256(dest) };
}

function buildManifest(ready, hashes) {
  return {
    pixelSize: PIXEL_SIZE,
    displayPt: PIXEL_SIZE / 3,
    source: 'recipe-scaler-web/recipe-scaler/public/assets/illustrations/empty-states',
    entries: ready.map((e) => ({
      webId: e.id,
      assetName: WEB_ID_TO_ASSET[e.id],
      sha256: hashes[e.id],
    })),
  };
}

function main() {
  if (!fs.existsSync(REGISTRY_PATH)) {
    console.error(`Registry not found: ${REGISTRY_PATH}`);
    process.exit(1);
  }
  if (!fs.existsSync(WEB_IMAGES_DIR)) {
    console.error(`Web images dir not found: ${WEB_IMAGES_DIR}`);
    process.exit(1);
  }

  const ready = readReadyEntries();
  const hashes = {};

  for (const entry of ready) {
    const assetName = WEB_ID_TO_ASSET[entry.id];
    const result = syncOne(entry.id, assetName);
    if (!result.ok) {
      console.error(result.error);
      process.exit(1);
    }
    hashes[entry.id] = result.hash;
  }

  const manifest = buildManifest(ready, hashes);
  const canonical = JSON.stringify(manifest.entries.map((e) => e.sha256));

  if (CHECK_ONLY) {
    if (!fs.existsSync(MANIFEST_PATH)) {
      console.error(`Manifest missing: ${MANIFEST_PATH}`);
      process.exit(1);
    }
    const existing = JSON.parse(fs.readFileSync(MANIFEST_PATH, 'utf8'));
    const existingCanonical = JSON.stringify(
      (existing.entries ?? []).map((e) => e.sha256),
    );
    if (existingCanonical !== canonical || existing.pixelSize !== PIXEL_SIZE) {
      console.error('Empty-state illustration assets out of sync with web sources');
      process.exit(1);
    }
    console.log(`OK check: ${ready.length} empty-state imagesets, ${PIXEL_SIZE}px`);
    return;
  }

  fs.writeFileSync(MANIFEST_PATH, JSON.stringify(manifest, null, 2) + '\n', 'utf8');
  console.log(
    `Synced ${ready.length} empty-state imagesets (${PIXEL_SIZE}px) → ${ASSETS_DIR}`,
  );
}

main();