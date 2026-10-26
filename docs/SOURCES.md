# Custom sources (advanced, off by default)

The app ships with **no sources and no repository addresses**. Users can turn on
Settings > Enable custom sources and add a source definition by HTTPS address.

## Definition format (JSON)

```json
{
  "id": "example.source",
  "name": "Example",
  "version": "1.0.0",
  "hosts": ["example.com"],
  "script": "var source = { search: async function(query, page) { ... } };"
}
```

- `hosts`: the only domains the script may reach (subdomains included). HTTPS only.
- `script`: JavaScript run in JavaScriptCore. No file or system access.

## Script API

Define a global `source` object. Each function may be `async` and must return plain data:

| Function | Returns |
| --- | --- |
| `search(query, page)` | `[{ id, title, coverURL? }]` |
| `details(mangaId)` | `{ title?, coverURL?, author?, summary? }` |
| `chapters(mangaId)` | `[{ id, name, number? }]` |
| `pages(chapterId)` | `[{ url, headers? }]` |

Available host function: `fetch(url, { method?, headers?, body? })` resolves to
`{ status, headers, text, json() }`. Requests are rate limited (one per 0.4 s), capped at
10 MB, and blocked outside `hosts` (including redirects). Calls time out after 60 s.

## Safety notes

- Off by default; confirmation shows the declared hosts before installing.
- Sources can be removed in Settings at any time.
- Apple's App Review Guideline 2.5.2 restricts apps that download executable code. This
  feature may be rejected on the App Store; consider shipping it only in TestFlight/AltStore builds.
