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
const THUMBS_MANIFEST_PATH = path.join(
  WEB_ROOT,
  'recipe-scaler/src/data/ingredient-illustrations/thumbs-manifest.json',
);
const WEB_THUMBS_DIR = path.join(
  WEB_ROOT,
  'recipe-scaler/public/assets/illustrations/ingredients/web',
);

const CORE_RESOURCES = path.join(NATIVE_ROOT, 'RecipeScalerCore/Resources');
const CATALOG_JSON = path.join(CORE_RESOURCES, 'ingredient-catalog.json');
const CATALOG_RU_JSON = path.join(CORE_RESOURCES, 'ingredient-catalog.ru.json');
const CATALOG_EN_JSON = path.join(CORE_RESOURCES, 'ingredient-catalog.en.json');
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

/**
 * Picker display order, computed once at build time so the runtime search path
 * stays filter-only (parity with web commit 3e6cce9).
 *
 * @param {Array<NonNullable<ReturnType<typeof buildCatalogEntries>[number]>>} rows
 * @param {'ru' | 'en'} locale
 */
function sortEntriesForPicker(rows, locale) {
  const labelKey = locale === 'ru' ? 'labelRu' : 'labelEn';
  return [...rows].sort((a, b) => {
    const cmp = a[labelKey].localeCompare(b[labelKey], locale, { sensitivity: 'base' });
    if (cmp !== 0) return cmp;
    return a.id.localeCompare(b.id);
  });
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

const THUMB_EXTENSION = 'webp';

/**
 * Web thumbs are cached as content-hashed, immutable files (`{id}-{hash}.webp`)
 * since web commit 241552a7. The id → hash mapping lives in
 * `thumbs-manifest.json` next to the registry. Native bundling strips the hash
 * (`{id}.webp`) so the iOS image store can look thumbs up by ingredient id
 * without a manifest dependency.
 *
 * Returns a map id → source filename. Entries missing from the manifest fall
 * back to the legacy `{id}.webp` name (so the script keeps working on older
 * web checkouts that did not yet hash their thumbs).
 */
function readWebThumbFilenames(readyIds) {
  let manifest = null;
  if (fs.existsSync(THUMBS_MANIFEST_PATH)) {
    try {
      manifest = JSON.parse(fs.readFileSync(THUMBS_MANIFEST_PATH, 'utf8'));
    } catch (err) {
      console.error(`Failed to parse ${THUMBS_MANIFEST_PATH}: ${err.message}`);
      process.exit(1);
    }
  }
  const entries = manifest?.entries ?? {};
  const out = new Map();
  for (const id of readyIds) {
    const hash = entries[id];
    out.set(id, hash ? `${id}-${hash}.${THUMB_EXTENSION}` : `${id}.${THUMB_EXTENSION}`);
  }
  return out;
}

function syncThumbs(webFilenames) {
  const missing = [];
  for (const [id, srcName] of webFilenames) {
    const src = path.join(WEB_THUMBS_DIR, srcName);
    if (!fs.existsSync(src)) {
      missing.push(`${id} (looked for ${srcName})`);
      continue;
    }
    if (!CHECK_ONLY) {
      fs.copyFileSync(src, path.join(NATIVE_THUMBS_DIR, `${id}.${THUMB_EXTENSION}`));
    }
  }
  return missing;
}

function removeLegacyJpgThumbs() {
  if (!fs.existsSync(NATIVE_THUMBS_DIR)) return 0;
  let removed = 0;
  for (const file of fs.readdirSync(NATIVE_THUMBS_DIR)) {
    if (!file.endsWith('.jpg')) continue;
    fs.unlinkSync(path.join(NATIVE_THUMBS_DIR, file));
    removed += 1;
  }
  return removed;
}

function countNativeThumbs() {
  if (!fs.existsSync(NATIVE_THUMBS_DIR)) return 0;
  return fs.readdirSync(NATIVE_THUMBS_DIR).filter((f) => f.endsWith(`.${THUMB_EXTENSION}`)).length;
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

  const webFilenames = readWebThumbFilenames(readyIds);
  const missing = syncThumbs(webFilenames);
  if (!CHECK_ONLY) {
    const removedJpg = removeLegacyJpgThumbs();
    if (removedJpg > 0) {
      console.log(`Removed ${removedJpg} legacy JPG thumb(s) from ${NATIVE_THUMBS_DIR}`);
    }
  }
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
    if (!fs.existsSync(CATALOG_RU_JSON) || !fs.existsSync(CATALOG_EN_JSON)) {
      console.error('Pre-sorted picker catalog (ru/en) missing in Core Resources');
      process.exit(1);
    }
    const existingManifest = JSON.parse(fs.readFileSync(MANIFEST_JSON, 'utf8'));
    const existingCatalog = JSON.parse(fs.readFileSync(CATALOG_JSON, 'utf8'));
    const existingCatalogEntries = existingCatalog.entries ?? [];
    const existingVersion = catalogVersion(
      canonicalCatalogJson(existingCatalogEntries),
    );
    if (existingManifest.catalogVersion !== version || existingVersion !== version) {
      console.error(
        `catalogVersion drift: manifest=${existingManifest.catalogVersion} computed=${version}`,
      );
      process.exit(1);
    }
    const existingRu = JSON.parse(fs.readFileSync(CATALOG_RU_JSON, 'utf8'));
    const existingEn = JSON.parse(fs.readFileSync(CATALOG_EN_JSON, 'utf8'));
    const expectedRu = JSON.stringify({ entries: sortEntriesForPicker(existingCatalogEntries, 'ru') }, null, 2) + '\n';
    const expectedEn = JSON.stringify({ entries: sortEntriesForPicker(existingCatalogEntries, 'en') }, null, 2) + '\n';
    const actualRu = JSON.stringify({ entries: existingRu.entries ?? [] }, null, 2) + '\n';
    const actualEn = JSON.stringify({ entries: existingEn.entries ?? [] }, null, 2) + '\n';
    if (actualRu !== expectedRu) {
      console.error('ingredient-catalog.ru.json drift: entries are not sorted by labelRu');
      process.exit(1);
    }
    if (actualEn !== expectedEn) {
      console.error('ingredient-catalog.en.json drift: entries are not sorted by labelEn');
      process.exit(1);
    }
    console.log(`OK check: ${readyIds.length} thumbs, catalogVersion=${version}`);
    return;
  }

  fs.writeFileSync(CATALOG_JSON, JSON.stringify({ entries }, null, 2) + '\n', 'utf8');
  fs.writeFileSync(CATALOG_RU_JSON, JSON.stringify({ entries: sortEntriesForPicker(entries, 'ru') }, null, 2) + '\n', 'utf8');
  fs.writeFileSync(CATALOG_EN_JSON, JSON.stringify({ entries: sortEntriesForPicker(entries, 'en') }, null, 2) + '\n', 'utf8');
  fs.writeFileSync(MANIFEST_JSON, JSON.stringify(manifest, null, 2) + '\n', 'utf8');
  console.log(
    `Synced ${readyIds.length} entries, catalogVersion=${version}, thumbs → ${NATIVE_THUMBS_DIR}`,
  );
}

main();