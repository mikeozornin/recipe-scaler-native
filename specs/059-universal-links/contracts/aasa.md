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
          "/public/@/*"
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

## Explicitly NOT claimed

| Path | Behavior |
|------|----------|
| `/public/{recipeId}` (legacy, no `@`) | Safari / web |
| `/public/shopping-list/{publicId}` | Safari / web |
| `/oauth/*`, `/#/*`, `/discover/*` | unchanged |

## Team / Bundle

- Team ID: `ZBPX4JYT24`
- Bundle ID (main): `ru.recipescaler.RecipeScaler`
- App ID string: `{TEAMID}.{BUNDLEID}`
