#!/usr/bin/env python3
"""Generate synthetic third-party import fixtures for unit tests."""

import gzip
import json
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "RecipeScalerNativeTests" / "Fixtures" / "ThirdPartyImport"
EXPECTED = FIXTURES / "expected"


def write_gzip_json(path: Path, payload: dict) -> None:
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    with gzip.open(path, "wb") as handle:
        handle.write(data)


def paprika_recipe(name: str, ingredients: str, directions: str, **extra) -> dict:
    recipe = {
        "name": name,
        "ingredients": ingredients,
        "directions": directions,
        "servings": "4",
    }
    recipe.update(extra)
    return recipe


def crouton_recipe(name: str, ingredients: list, steps: list, **extra) -> dict:
    recipe = {
        "uuid": f"uuid-{name.lower().replace(' ', '-')}",
        "name": name,
        "serves": 2,
        "ingredients": ingredients,
        "steps": steps,
    }
    recipe.update(extra)
    return recipe


def main() -> None:
    FIXTURES.mkdir(parents=True, exist_ok=True)
    EXPECTED.mkdir(parents=True, exist_ok=True)

    minimal_paprika = paprika_recipe(
        "Test Paprika Recipe",
        "200 g flour\n3 eggs\n salt ",
        "1. Mix flour and eggs.\n2. Bake for 30 minutes.",
        notes="Best served warm.",
        prep_time="15 min",
        cook_time="30 min",
        categories=["Dinner", "Quick"],
        source="Test Kitchen",
        source_url="https://example.com/recipe",
    )
    write_gzip_json(FIXTURES / "paprika-minimal.paprikarecipe", minimal_paprika)
    (EXPECTED / "paprika-minimal.json").write_text(
        json.dumps(
            {"name": "Test Paprika Recipe", "ingredientCount": 3, "stepCount": 2},
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )

    archive_path = FIXTURES / "paprika-three.paprikarecipes"
    with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for index in range(1, 4):
            payload = paprika_recipe(
                f"Paprika Recipe {index}",
                f"{index * 100} g flour\n1 egg",
                f"{index}. Combine.\n{index + 1}. Serve.",
            )
            buffer = gzip.compress(json.dumps(payload).encode("utf-8"))
            archive.writestr(f"recipe-{index}.paprikarecipe", buffer)

    (EXPECTED / "paprika-three.json").write_text(
        json.dumps({"recipeCount": 3}, indent=2) + "\n",
        encoding="utf-8",
    )

    minimal_crouton = crouton_recipe(
        "Test Crouton Salad",
        [
            {
                "quantity": {"amount": 225, "quantityType": "GRAMS"},
                "ingredient": {"name": "Cucumber", "uuid": "ing-1"},
                "order": 0,
            },
            {
                "quantity": {"amount": 2, "quantityType": "TABLESPOONS"},
                "ingredient": {"name": "Olive oil", "uuid": "ing-2"},
                "order": 1,
            },
        ],
        [
            {"step": "Chop cucumber", "order": 0, "isSection": False},
            {"step": "Dressing", "order": 1, "isSection": True},
            {"step": "Mix oil and vinegar", "order": 2, "isSection": False},
        ],
    )
    (FIXTURES / "crouton-minimal.crumb").write_text(
        json.dumps(minimal_crouton, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    (EXPECTED / "crouton-minimal.json").write_text(
        json.dumps(
            {"name": "Test Crouton Salad", "ingredientCount": 2, "stepCount": 2},
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )

    batch_path = FIXTURES / "crouton-batch.zip"
    batch_recipes = [
        crouton_recipe(
            "Crouton Soup",
            [
                {
                    "quantity": {"amount": 500, "quantityType": "MILLILITERS"},
                    "ingredient": {"name": "Broth", "uuid": "ing-a"},
                    "order": 0,
                }
            ],
            [{"step": "Simmer broth", "order": 0, "isSection": False}],
        ),
        crouton_recipe(
            "Crouton Salad",
            [
                {
                    "quantity": {"amount": 1, "quantityType": "PIECES"},
                    "ingredient": {"name": "Lettuce", "uuid": "ing-b"},
                    "order": 0,
                },
                {
                    "quantity": {"amount": 3, "quantityType": "TABLESPOONS"},
                    "ingredient": {"name": "Vinaigrette", "uuid": "ing-c"},
                    "order": 1,
                },
            ],
            [
                {"step": "Prep", "order": 0, "isSection": True},
                {"step": "Wash lettuce", "order": 1, "isSection": False},
                {"step": "Toss with dressing", "order": 2, "isSection": False},
            ],
        ),
        crouton_recipe(
            "Crouton Toast",
            [
                {
                    "quantity": {"amount": 2, "quantityType": "PIECES"},
                    "ingredient": {"name": "Bread slice", "uuid": "ing-d"},
                    "order": 0,
                }
            ],
            [{"step": "Toast bread", "order": 0, "isSection": False}],
        ),
    ]

    with zipfile.ZipFile(batch_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for recipe in batch_recipes:
            file_name = f"{recipe['name'].lower().replace(' ', '-')}.crumb"
            archive.writestr(
                file_name,
                json.dumps(recipe, ensure_ascii=False, indent=2) + "\n",
            )

    (EXPECTED / "crouton-batch.json").write_text(
        json.dumps({"recipeCount": 3}, indent=2) + "\n",
        encoding="utf-8",
    )

    print(f"Fixtures written to {FIXTURES}")


if __name__ == "__main__":
    main()
