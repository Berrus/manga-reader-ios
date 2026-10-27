# OPDS catalogs (Kavita, Komga and others)

Settings > Library > Servers > **Add OPDS catalog…** connects to an OPDS catalog you run yourself. Series come from the catalog's entries and chapters are read page by page through OPDS page streaming (PSE), so nothing has to be downloaded first. Chapters can then be downloaded for offline reading like any other remote series.

## Kavita

1. In Kavita, open your user preferences and copy your **OPDS URL**. It already contains your API key, e.g. `http://192.168.1.10:5000/api/opds/<your key>`.
2. Paste it as the catalog address. Leave the username and password empty. **Test connection** shows the catalog name.

Kavita's own REST API (its login and JWT) is **not** implemented; Kavita works through its OPDS feed only.

## Komga

Komga is better served by its own client (Settings > Servers > Add Komga server). Its OPDS feed also works: use `http://host:25600/opds/v1.2/catalog` with your Komga username and password.

## What is shown

- Entries that link to another feed are series; the first screen of the catalog you enter is the list searched, so point it at a library or "all series" feed. Search uses the catalog's OpenSearch link when it has one; otherwise the list is filtered by title.
- Entries with a page-streaming link are chapters. Volumes that contain chapters are followed one level down.
- Books offered only as a whole-file download (no streaming link) are not shown. There is no OPDS file download.
- Plain `http://` is accepted only for local-network addresses.

Not verified against a real Kavita server: the parser is tested against a Kavita-style sample feed only.
