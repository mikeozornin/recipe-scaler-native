#!/usr/bin/env node
/**
 * Типограф для Localizable.xcstrings
 *
 * Применяет правила typograf (умные кавычки, тире, неразрывные пробелы и т.п.)
 * только к русским value, не затрагивая ключи, английские строки и форматирование Xcode.
 *
 * Запуск:
 *   bun run scripts/typograf.mjs
 *   node scripts/typograf.mjs
 *
 * Зависимость — typograf@7.7.0 из веб-проекта (установка не требуется).
 */

import { readFileSync, writeFileSync } from 'fs';
import { createRequire } from 'module';
import { fileURLToPath } from 'url';
import { resolve, dirname } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));

// ─── Загрузка typograf из соседнего веб-проекта (без установки) ───────────────
const TYPOGRAF_PATH = resolve(
  __dirname,
  '../../recipe-scaler-web/recipe-scaler/node_modules/typograf/dist/typograf.es.mjs'
);

let Typograf;
try {
  ({ default: Typograf } = await import(TYPOGRAF_PATH));
} catch {
  console.error(`❌ Не удалось загрузить typograf по пути:\n   ${TYPOGRAF_PATH}`);
  console.error('   Убедитесь, что зависимости веб-проекта установлены: bun install');
  process.exit(1);
}

const tp = new Typograf({ locale: ['ru'], htmlEntity: false });
tp.disableRule('common/html/stripTags');

// ─── Путь к файлу ─────────────────────────────────────────────────────────────
const XCSTRINGS_PATH = resolve(
  __dirname,
  '../RecipeScalerNative/Resources/Localizable.xcstrings'
);

// ─── Хирургическая построчная обработка ──────────────────────────────────────
//
// Xcode записывает локализации примерно так:
//
//   "ru" : {
//     "stringUnit" : {
//       "state" : "translated",
//       "value" : "Аватар обновлён"
//     }
//   }
//
// Идём построчно, отслеживаем открывашку языкового блока ("ru" : {)
// и применяем typograf только к строкам "value" : "..." внутри ru-блока.

const LANG_OPEN_RE = /^(\s*)"(en|ru)"\s*:\s*\{\s*$/;
const VALUE_LINE_RE = /^(\s*"value"\s*:\s*)("(?:[^"\\]|\\.)*")(,?)(\s*)$/;

console.log('🚀 Запуск типографа...\n');

const raw = readFileSync(XCSTRINGS_PATH, 'utf8');
const lines = raw.split('\n');

let currentLang = null;
let processed = 0;
let changed = 0;

const result = lines.map((line) => {
  // Обновляем текущий язык при открывашке блока
  const langMatch = LANG_OPEN_RE.exec(line);
  if (langMatch) {
    currentLang = langMatch[2]; // 'en' или 'ru'
    return line;
  }

  // Сбрасываем язык при закрывающей скобке на том же уровне
  // (достаточно сброса на любую закрывашку — вложенность гарантирована форматом Xcode)
  if (/^\s*\}\s*,?\s*$/.test(line)) {
    currentLang = null;
    return line;
  }

  // Обрабатываем value только в русских блоках
  if (currentLang !== 'ru') return line;

  const valueMatch = VALUE_LINE_RE.exec(line);
  if (!valueMatch) return line;

  const [, prefix, jsonLiteral, comma, trail] = valueMatch;
  processed++;

  let original;
  try {
    original = JSON.parse(jsonLiteral);
  } catch {
    console.warn(`  ⚠️  Не удалось распарсить JSON-литерал: ${jsonLiteral}`);
    return line;
  }

  const typografed = tp.execute(original);
  if (typografed === original) return line;

  changed++;
  // JSON.stringify экранирует спецсимволы и сохраняет кириллицу как сырые символы
  const newLiteral = JSON.stringify(typografed);
  return `${prefix}${newLiteral}${comma}${trail}`;
});

const output = result.join('\n');

if (changed === 0) {
  console.log(`✅ Без изменений (проверено ${processed} ru-значений)`);
} else {
  writeFileSync(XCSTRINGS_PATH, output, 'utf8');
  console.log(`✅ Изменено ${changed} из ${processed} ru-значений`);
  console.log(`📄 ${XCSTRINGS_PATH}`);
}

console.log('\n🎉 Готово!');
