# Declarative custom sources

Custom sources are optional and off by default. Add an HTTPS JSON definition in Settings.
Definitions are data: no JavaScript is executed, including during validation or installation.
Previously installed script definitions are retained on disk but disabled; replace them with this format.

Each operation specifies a GET URL, an optional dot-separated JSON items path, and a field map.
Path components may be object keys or zero-based array indices. Empty paths select the whole value.
Placeholders are percent-encoded before substitution: search accepts {query}/{page}; the other operations accept {id}.

```json
{
  "id": "example.source",
  "name": "My media source",
  "version": "1",
  "hosts": ["example.com"],
  "endpoints": {
    "search": {"url": "https://example.com/api/search?q={query}&page={page}", "itemsPath": "data", "fields": {"id": "id", "title": "name", "coverURL": "cover"}},
    "details": {"url": "https://example.com/api/books/{id}", "fields": {"title": "name", "summary": "description"}},
    "chapters": {"url": "https://example.com/api/books/{id}/chapters", "itemsPath": "data", "fields": {"id": "id", "name": "title", "number": "number"}},
    "pages": {"url": "https://example.com/api/chapters/{id}/pages", "itemsPath": "data", "fields": {"url": "image"}}
  }
}
```

All endpoints, covers, page images and redirects must use the declared HTTPS domains (subdomains included).
JSON responses are limited to 10 MB; image bodies are bounded while receiving bytes.
Cookies and shared URL credentials are not available to custom sources.
No sources or repository lists are bundled.
