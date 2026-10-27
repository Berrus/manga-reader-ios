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


## Repository catalogs

Enable custom sources, then open Settings → Installed sources → Source repositories. Add an HTTPS URL to a JSON object with `version: 1` and a `sources` array of the full declarative definitions above:

```json
{"version":1,"sources":[{"id":"example.source","name":"Example","version":"1","hosts":["example.com"],"endpoints":{"search":{"url":"https://example.com/search?q={query}","fields":{"id":"id","title":"name"}},"details":{"url":"https://example.com/books/{id}","fields":{}},"chapters":{"url":"https://example.com/books/{id}/chapters","fields":{"id":"id","name":"name"}},"pages":{"url":"https://example.com/chapters/{id}/pages","fields":{"url":"url"}}}}]}
```

Repositories are limited to 20 addresses, 1 MB per catalog and 200 entries. Refresh explicitly reloads the selected catalog; install/update asks for confirmation and shows allowed domains. Removing a repository does not remove installed sources. APK, Paperback and Aidoku extensions are not compatible with this format. The App Store configuration also provides opt-in declarative sources; built-in MangaDex browsing remains excluded.

## Replacing installed sources

The app remembers which repository each source came from. If a repository tries to install a
source whose id is already installed but with different domains, or from a different repository,
the confirmation shows a warning naming the old and new domains and the button becomes "Replace
source". Plain updates (same domains, same repository) are unchanged. The same check applies to sources added by direct address (Settings > Add source), which records the address as the origin, and it is enforced inside `SourceStore.add`, so a caller that skips the warning gets an error instead of a silent replacement.
