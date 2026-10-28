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

Repositories are limited to 20 addresses, 1 MB per catalog and 200 entries. Refresh explicitly reloads the selected catalog; install/update asks for confirmation and shows allowed domains. Removing a repository does not remove installed sources. APK, Paperback and Aidoku extensions are not compatible with this format. The App Store configuration also provides opt-in declarative sources; the built-in MangaDex API provider has been removed.

## Replacing installed sources

The app remembers which repository each source came from. If a repository tries to install a
source whose id is already installed but with different domains, or from a different repository,
the confirmation shows a warning naming the old and new domains and the button becomes "Replace
source". Plain updates (same domains, same repository) are unchanged.


## Scripted (JavaScript) sources — non-App-Store builds only

Settings → Installed sources → Scripted sources. Off by default, separate from declarative sources, and the
code is not compiled into the `AppStore` configuration (`DistributionPolicy.allowsScriptedSources` is false there).
No sources or repositories are included; paste the address of a manifest:

```json
{"id":"example","name":"Example","version":"1","hosts":["example.com","cdn.example.com"],
 "entry":"https://example.com/source.js","sha256":"<hex SHA-256 of the script file>"}
```

The script is downloaded over HTTPS (max 256 KB) and must match `sha256`; it is re-checked on every load.
It defines global functions that return plain data:

```js
function search(query, page) { return [{id: "1", title: "Name", coverURL: "https://cdn.example.com/c.jpg"}]; }
function details(id)  { return {title: "Name", author: "A", summary: "S", coverURL: "..."}; }
function chapters(id) { return [{id: "c1", name: "Chapter 1", number: 1}]; }
function pages(id)    { return [{url: "https://cdn.example.com/1.jpg"}]; }
```

The only host functions are `http.get(url, headers)` → `{status, body}` (declared HTTPS hosts only, no cookies or
Authorization, 10 MB, 30 calls per run) and `log(text)`. There is no DOM: parse `body` with JavaScript string and
regular-expression functions. Limits: 20 s per call, 1000 items per result. JavaScriptCore cannot be interrupted, so a
script that never returns keeps its thread until the app quits; after three such runs scripted sources stop running.
Image URLs must be on declared hosts. Paperback and Aidoku packages are not compatible.


## Paperback 0.9 repositories — non-App-Store builds only

Settings → Installed sources → Paperback extensions. Off by default. Turn it on, paste a repository base address
(for example the one Paperback itself uses: `https://…/0.9/stable`), open it to see its extensions and tap Install.
Nothing is pre-filled. Extensions appear in Browse like other sources and use ids starting with `pb.`.

Folio reads the repository's `versioning.json` and downloads `<id>/index.js` for each extension you install. Extensions
rated ADULT in the repository are not listed. A small compatibility layer (Sources/PaperbackShim.swift) provides the part
of Paperback's `Application` API that library extensions use: HTTPS requests with their request/response interceptors,
HTML entity decoding, per-extension state and timers. Search, details, chapters and pages are supported.

Not supported: extension settings forms, login and secure storage (kept in memory only), discover sections, tag filters and
search filters, and Paperback's own tracker or notification features. An extension that needs those may load but behave
partly. Extensions declare no domains, so they may contact any public HTTPS site (never local or private addresses, never
with stored cookies or credentials). Repository scripts carry no checksum, so you are trusting the repository host.
Paperback extensions were run against this layer in a Node test harness with mocked network responses; they have not been run on a device.
