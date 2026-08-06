#!/usr/bin/env python3
"""Build store/fixtures/recipes-{ru,en}.zip from a full Recipe Scaler export.

Keeps only recipes that have images/<id>/full.webp. Rewrites metadata to v1.4
so native NativeRecipeImporter accepts the archive.
"""

from __future__ import annotations

import argparse
import io
import json
import re
import sys
import zipfile
from pathlib import Path

from store_en_descriptions import DESCRIPTIONS_EN

PRIMARY_ID = "5928ae97-2e6e-4f86-8bbc-6f0380e4ac42"
CYRILLIC_RE = re.compile(r"[А-Яа-яЁё]")

RECIPE_NAMES_EN = {
    "Оссобуко": "Ossobuco",
    "Печенье с лимоном, розмарином и лимонным курдом": "Lemon Rosemary Cookies with Lemon Curd",
    "Печенье с шоколадом": "Chocolate Cookies",
    "🍣 Соленый лосось": "🍣 Salt-Cured Salmon",
    "Сырники": "Syrniki",
    "Тертый пирог со сливами": "Grated Plum Pie",
    "🍲 Финский рыбный суп лохикейтто": "🍲 Finnish Salmon Soup Lohikeitto",
    "Шарлотка": "Charlotte",
    "Шоколадный фондан": "Chocolate Fondant",
    "Штрудель": "Strudel",
    "Эклер с черной смородиной": "Blackcurrant Eclair",
}

INGREDIENT_NAMES_EN = {
    "Говяжьи голяшки, штуки": "Beef shanks",
    "Репчатый лук, штуки": "Yellow onions",
    "Стебель сельдерея, штуки": "Celery stalks",
    "Морковь, штуки": "Carrots",
    "Чеснок, зубчика": "Garlic cloves",
    "Белое сухое вино, мл": "Dry white wine",
    "Куриный бульон, мл": "Chicken stock",
    "Петрушка, г": "Parsley",
    "Лимонная цедра, столовые ложки": "Lemon zest",
    "Оливковое масло, мл": "Olive oil",
    "Сливочное масло, г": "Butter",
    "Соль, по вкусу": "Salt",
    "Сахар, по вкусу": "Sugar",
    "Молотый черный перец, по вкусу": "Ground black pepper",
    "Консервированные помидоры кусочками, г": "Canned chopped tomatoes",
    "Для лимонного курда (начинка)": "Lemon curd filling",
    "Лимонный сок, мл": "Lemon juice",
    "Сахар, г": "Sugar",
    "Яичные желтки, шт": "Egg yolks",
    "Цедра лимона, шт": "Lemon zest",
    "Для теста": "Dough",
    "Белый сахар, г": "White sugar",
    "Коричневый сахар, г": "Brown sugar",
    "Соль, г": "Salt",
    "Сода, г": "Baking soda",
    "Яйца, г": "Eggs",
    "Мука, г": "Flour",
    "Кукурузный крахмал, г": "Cornstarch",
    "Розмарин свежий (мелко рубленный), ст. л.": "Fresh rosemary, finely chopped",
    "Лимонный сок, ст. л.": "Lemon juice",
    "Мука средней силы, г": "All-purpose flour",
    "Кукурузный крахм., г": "Cornstarch",
    "Шоколадные капли, г": "Chocolate chips",
    "Творог, г": "Farmer cheese",
    "Куриное яйцо, штука": "Egg",
    "Пшеничная мука, г": "Wheat flour",
    "Растительное масло, мл": "Vegetable oil",
    "Ванилин, г": "Vanillin",
    "Сметана, по вкусу": "Sour cream",
    "Масло сливочное, г": "Butter",
    "Соль, щепотка": "Salt",
    "Разрыхлитель, чайная ложка": "Baking powder",
    "Вода, столовые ложки": "Water",
    "Яичный желток, штуки": "Egg yolk",
    "Сливы, г": "Plums",
    "Лук-порей, штуки": "Leeks",
    "Вода, л": "Water",
    "Картофель, кг": "Potatoes",
    "Лавровый лист, штука": "Bay leaf",
    "Филе лосося, г": "Salmon fillet",
    "Сливки 30%, л": "Heavy cream 30%",
    "Укроп, г": "Dill",
    "Тесто": "Dough",
    "Яйца": "Eggs",
    "Сахар, г": "Sugar",
    "Растительное масло, г": "Vegetable oil",
    "Сметана, г": "Sour cream",
    "Соль, ч. л.": "Salt",
    "Разрыхлитель, г": "Baking powder",
    "Начинка": "Filling",
    "Вишня, г": "Cherries",
    "Масло сливочное 82,5%, г": "Butter 82.5%",
    "Шоколад 70%, г": "70% chocolate",
    "Яйца, шт": "Eggs",
    "Желток, шт": "Egg yolk",
    "Сахар тростниковый, г": "Cane sugar",
    "Сахар, ч. л.": "Sugar",
    "Вода, мл": "Water",
    "Раст. масло, ст. л.": "Vegetable oil",
    "Крахмал, ст. л.": "Starch",
    "Молоко 3,2%, мл": "Whole milk 3.2%",
    "Куриное яйцо, штук": "Eggs",
    "Крем": "Cream",
    "Куриное яйцо, шт": "Egg",
    "Черная смородина, г": "Blackcurrants",
    "Сливки 33%, мл": "Heavy cream 33%",
    "Крахмал, г": "Starch",
    "Шоколад, г": "Chocolate",
    "Штруделей": "Strudels",
}

UNIT_EN = {
    "г": "g",
    "грамм": "g",
    "мл": "ml",
    "л": "l",
    "кг": "kg",
    "ч. л.": "tsp",
    "чайная ложка": "tsp",
    "ст. л.": "tbsp",
    "столовые ложки": "tbsp",
    "шт": "pcs",
    "штук": "pcs",
    "штука": "pc",
    "штуки": "pcs",
    "зубчика": "cloves",
    "по вкусу": "to taste",
    "щепотка": "pinch",
}

def imaged_ids(zf: zipfile.ZipFile) -> set[str]:
    ids: set[str] = set()
    for name in zf.namelist():
        if name.startswith("images/") and "/full." in name:
            parts = name.split("/")
            if len(parts) >= 2:
                ids.add(parts[1])
    return ids


def translate_ingredient(ing: dict, errors: list[str]) -> dict:
    out = dict(ing)
    name = ing.get("name") or ""
    unit = ing.get("unit") or ""
    if name in INGREDIENT_NAMES_EN:
        out["name"] = INGREDIENT_NAMES_EN[name]
    elif name:
        errors.append(f"untranslated ingredient {name!r}")
    if unit in UNIT_EN:
        out["unit"] = UNIT_EN[unit]
    elif unit:
        errors.append(f"untranslated unit {unit!r} for {name!r}")
    return out


def translate_recipe(recipe: dict, errors: list[str]) -> dict:
    out = dict(recipe)
    name = recipe.get("name") or ""
    if name not in RECIPE_NAMES_EN:
        errors.append(f"untranslated recipe name {name!r}")
    out["name"] = RECIPE_NAMES_EN.get(name, name)
    out["ingredients"] = [
        translate_ingredient(i, errors) for i in recipe.get("ingredients") or []
    ]
    recipe_id = recipe.get("id") or ""
    description = DESCRIPTIONS_EN.get(recipe_id)
    if not description:
        errors.append(f"missing EN description for {recipe_id} ({name!r})")
    else:
        if CYRILLIC_RE.search(description):
            errors.append(f"Cyrillic left in EN description for {recipe_id}")
        out["description"] = description
    return out


def write_zip(path: Path, payload: dict, zf_src: zipfile.ZipFile, keep_ids: set[str]) -> None:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", compression=zipfile.ZIP_DEFLATED) as out:
        out.writestr("recipes.json", json.dumps(payload, ensure_ascii=False, indent=2))
        for name in zf_src.namelist():
            if not name.startswith("images/"):
                continue
            rid = name.split("/")[1] if "/" in name else ""
            if rid in keep_ids:
                out.writestr(name, zf_src.read(name))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(buf.getvalue())


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--input",
        default=str(Path.home() / "Downloads/recipe-scaler-2026-08-05T11-55-40-294Z.zip"),
    )
    parser.add_argument(
        "--out-dir",
        default=str(Path(__file__).resolve().parents[1] / "store" / "fixtures"),
    )
    args = parser.parse_args()

    src = Path(args.input)
    if not src.is_file():
        sys.stderr.write(f"missing input zip: {src}\n")
        return 1

    with zipfile.ZipFile(src) as zf:
        data = json.loads(zf.read("recipes.json"))
        keep = imaged_ids(zf)
        recipes = [r for r in data.get("recipes") or [] if r.get("id") in keep]
        if len(recipes) != 11:
            sys.stderr.write(f"expected 11 imaged recipes, got {len(recipes)}\n")
            return 1
        if not any(r.get("id") == PRIMARY_ID for r in recipes):
            sys.stderr.write("primary Strudel recipe missing\n")
            return 1

        image_files = data.get("imageFiles") or {}
        if isinstance(image_files, dict):
            image_files = {k: v for k, v in image_files.items() if k in keep}

        ru_payload = {
            "metadata": {
                "version": "1.4",
                "exportDate": (data.get("metadata") or {}).get("exportDate"),
                "type": "recipes-v1.4",
                "count": len(recipes),
            },
            "recipes": recipes,
            # Export folders have no recipe membership; empty folders would
            # only confuse the library UI. Mapping lives in collection Y.Doc.
            "folders": [],
            "imageFiles": image_files,
        }
        errors: list[str] = []
        en_payload = {
            **ru_payload,
            "recipes": [translate_recipe(r, errors) for r in recipes],
        }
        if errors:
            sys.stderr.write("EN translation incomplete:\n")
            for err in errors:
                sys.stderr.write(f"  - {err}\n")
            return 1

        out_dir = Path(args.out_dir)
        write_zip(out_dir / "recipes-ru.zip", ru_payload, zf, keep)
        write_zip(out_dir / "recipes-en.zip", en_payload, zf, keep)

    print(f"wrote {out_dir / 'recipes-ru.zip'}")
    print(f"wrote {out_dir / 'recipes-en.zip'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
