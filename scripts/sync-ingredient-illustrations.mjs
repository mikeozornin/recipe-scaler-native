#!/usr/bin/env node
/**
 * Sync ingredient illustration thumbs + compact catalog from recipe-scaler-web.
 *
 * Usage:
 *   node scripts/sync-ingredient-illustrations.mjs
 *   node scripts/sync-ingredient-illustrations.mjs --check
 *   WEB_ROOT=/path/to/recipe-scaler-web node scripts/sync-ingredient-illustrations.mjs
 */

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
  'recipe-scaler/src/data/ingredient-illustrations/registry.json',
);
const WEB_THUMBS_DIR = path.join(
  WEB_ROOT,
  'recipe-scaler/public/assets/illustrations/ingredients/web',
);

const CORE_RESOURCES = path.join(NATIVE_ROOT, 'RecipeScalerCore/Resources');
const CATALOG_JSON = path.join(CORE_RESOURCES, 'ingredient-catalog.json');
const MANIFEST_JSON = path.join(CORE_RESOURCES, 'ingredient-catalog.manifest.json');
const NATIVE_THUMBS_DIR = path.join(
  NATIVE_ROOT,
  'RecipeScalerNative/Resources/IngredientIllustrations',
);

const THUMB_PIXEL_SIZE = 120;
const CHECK_ONLY = process.argv.includes('--check');

function readRegistry() {
  const raw = fs.readFileSync(REGISTRY_PATH, 'utf8');
  const registry = JSON.parse(raw);
  const ready = (registry.entries ?? []).filter((e) => e.status === 'ready');
  ready.sort((a, b) => a.id.localeCompare(b.id));
  return ready;
}

function buildCatalogEntries(ready) {
  return ready.map((e) => ({
    id: e.id,
    category: e.category,
    labelRu: e.labelRu,
    labelEn: e.labelEn,
    aliasesRu: e.aliasesRu ?? [],
    aliasesEn: e.aliasesEn ?? [],
  }));
}

function canonicalCatalogJson(entries) {
  return JSON.stringify({ entries }, null, 0);
}

function catalogVersion(canonical) {
  return crypto.createHash('sha256').update(canonical, 'utf8').digest('hex').slice(0, 16);
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function syncThumbs(readyIds) {
  const missing = [];
  for (const id of readyIds) {
    const src = path.join(WEB_THUMBS_DIR, `${id}.jpg`);
    if (!fs.existsSync(src)) {
      missing.push(id);
      continue;
    }
    if (!CHECK_ONLY) {
      fs.copyFileSync(src, path.join(NATIVE_THUMBS_DIR, `${id}.jpg`));
    }
  }
  return missing;
}

function countNativeThumbs() {
  if (!fs.existsSync(NATIVE_THUMBS_DIR)) return 0;
  return fs.readdirSync(NATIVE_THUMBS_DIR).filter((f) => f.endsWith('.jpg')).length;
}

function main() {
  if (!fs.existsSync(REGISTRY_PATH)) {
    console.error(`Registry not found: ${REGISTRY_PATH}`);
    process.exit(1);
  }
  if (!fs.existsSync(WEB_THUMBS_DIR)) {
    console.error(`Web thumbs dir not found: ${WEB_THUMBS_DIR}`);
    process.exit(1);
  }

  const ready = readRegistry();
  const entries = buildCatalogEntries(ready);
  const canonical = canonicalCatalogJson(entries);
  const version = catalogVersion(canonical);
  const readyIds = entries.map((e) => e.id);

  if (!CHECK_ONLY) {
    ensureDir(CORE_RESOURCES);
    ensureDir(NATIVE_THUMBS_DIR);
  }

  const missing = syncThumbs(readyIds);
  if (missing.length > 0) {
    console.error(`Missing web thumbs (${missing.length}): ${missing.slice(0, 5).join(', ')}…`);
    process.exit(1);
  }

  const thumbCount = CHECK_ONLY ? countNativeThumbs() : readyIds.length;
  if (thumbCount !== readyIds.length) {
    console.error(
      `Thumb count mismatch: expected ${readyIds.length}, found ${thumbCount} in ${NATIVE_THUMBS_DIR}`,
    );
    process.exit(1);
  }

  const manifest = {
    catalogVersion: version,
    readyEntryCount: readyIds.length,
    thumbPixelSize: THUMB_PIXEL_SIZE,
    source: 'recipe-scaler-web/recipe-scaler/public/assets/illustrations/ingredients/web',
  };

  if (CHECK_ONLY) {
    if (!fs.existsSync(CATALOG_JSON) || !fs.existsSync(MANIFEST_JSON)) {
      console.error('Catalog or manifest missing in Core Resources');
      process.exit(1);
    }
    const existingManifest = JSON.parse(fs.readFileSync(MANIFEST_JSON, 'utf8'));
    const existingCatalog = fs.readFileSync(CATALOG_JSON, 'utf8');
    const existingVersion = catalogVersion(existingCatalog);
    if (existingManifest.catalogVersion !== version || existingVersion !== version) {
      console.error(
        `catalogVersion drift: manifest=${existingManifest.catalogVersion} computed=${version}`,
      );
      process.exit(1);
    }
    console.log(`OK check: ${readyIds.length} thumbs, catalogVersion=${version}`);
    return;
  }

  fs.writeFileSync(CATALOG_JSON, JSON.stringify({ entries }, null, 2) + '\n', 'utf8');
  fs.writeFileSync(MANIFEST_JSON, JSON.stringify(manifest, null, 2) + '\n', 'utf8');
  console.log(
    `Synced ${readyIds.length} entries, catalogVersion=${version}, thumbs → ${NATIVE_THUMBS_DIR}`,
  );
}

main();