# Contract: apple-app-site-association

**Host**: `https://recipe-scaler.ru`  
**URL**: `GET /.well-known/apple-app-site-association`  
**Content-Type**: `application/json`  
**Redirects**: none (nginx + Express must not 301/302)

## Body

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appID": "ZBPX4JYT24.ru.recipescaler.RecipeScaler",
        "paths": [
          "/public/@/*",
          "/recipe/*",
          "/discover/collection/*",
          "/discover/recipe/*",
          "/discover",
          "/shopping",
          "/"
        ]
      }
    ]
  }
}
```

## Claimed paths

| Path | Opens in app |
|------|----------------|
| `/public/@/{username}` | Discover public profile |
| `/public/@/{username}/{recipeId}` | Discover public recipe |
| `/recipe/{recipeId}` | My Recipes → recipe (parity with `recipe-scaler://recipe/`) |
| `/` | Recipes tab home (parity with `://home`) |
| `/shopping` | Shopping tab (parity with `://shopping`) |
| `/discover` | Discover tab root |
| `/discover/collection/{slug}` | Discover curated collection |
| `/discover/recipe/{recipeId}` | Discover curated recipe |

Do **not** claim bare `/discover/*` — only the collection/recipe prefixes above, so unknown `/discover/foo` stays in Safari.

## Explicitly NOT claimed

| Path | Behavior |
|------|----------|
| `/public/{recipeId}` (legacy, no `@`) | Safari / web |
| `/public/shopping-list/{publicId}` | Safari / web |
| `/oauth/*` | Safari / web (MCP OAuth) |
| `/about`, `/privacy`, `/account` | Safari / web |
| `/api/*`, `/mcp`, `/og/*` | infra |

## Team / Bundle

- Team ID: `ZBPX4JYT24`
- Bundle ID (main): `ru.recipescaler.RecipeScaler`
- App ID string: `{TEAMID}.{BUNDLEID}`
