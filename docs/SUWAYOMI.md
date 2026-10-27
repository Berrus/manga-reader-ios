# Suwayomi servers

Folio Reader can browse and read from a [Suwayomi](https://github.com/Suwayomi/Suwayomi-Server) server you run yourself. The app only connects to the address you enter; the content depends entirely on the extensions you install on your own server. No server address or extension list is bundled.

## Set up

1. Settings > Library > Servers > **Add Suwayomi server…**
2. Enter the server address (for example `http://192.168.1.10:4567`) and, if your server uses HTTP Basic authentication, a username and password. Leave both empty for a server with no login. **Test connection** shows the server name and version.
3. Browse > *Suwayomi servers* > your server lists its sources (extensions). Adult-only sources are hidden. Pick one to browse popular titles or search.
4. Open a series and **Add to library** to read it, download chapters, and receive update checks like any other remote series.

Passwords are stored in the Keychain. Plain `http://` is only accepted for addresses on your local network; use `https://` otherwise.

## What it uses

All calls are GraphQL requests to `<server>/api/graphql`:

| Feature | Operation |
| --- | --- |
| Connection test | `aboutServer { name version }` |
| Source list | `sources { nodes { id name lang displayName isNsfw } }` |
| Browse / search | `fetchSourceManga(input: { source, type: POPULAR or SEARCH, page, query })` |
| Details | `fetchManga(input: { id })` |
| Chapters | `fetchChapters(input: { mangaId })` |
| Pages | `fetchChapterPages(input: { chapterId })` (page paths are relative to the server) |

Library entries remember the source as `suwayomi.<server id>.<source id>`, so downloads and update checks keep working after a restart. Removing a server makes its library entries show "source unavailable" until it is added again.

## Limits

- Only servers with no login or HTTP Basic authentication. Servers using Suwayomi's UI login or simple login (cookie/JWT) are not supported and report that the sign-in was refused.
- The schema was written from Suwayomi-Server's documented GraphQL API and has **not** been run against a real server. Field names or behaviour may differ between server versions; the Test connection and the first browse are the quickest check.
- Fetching chapters asks the server to refresh from the source each time, so update checks on many Suwayomi series can be slow.
- Migration and the saved-search feed can use Suwayomi sources you have opened, but the migration destination picker lists only sources the app can enumerate without contacting a server.
- Controlled by `DistributionPolicy.allowsSuwayomi`, which follows `allowsCustomSources`. Turn that off for a build that must not include third-party-extension servers.
