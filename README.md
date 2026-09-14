<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the smddb project authors -->

# smddb

Two designs for the same model: `.smd`, a sidecar format describing series
structure that Emby's three fixed levels cannot hold, and the shared database
behind it, which knows what a container is and which pressing of which disc
holds each piece of it.

Nothing here is implemented. The repository is currently the argument, and the
two documents are meant to be read in order — the database mirrors the sidecar
one to one, so the format settles the vocabulary the schema then uses.

- [Proposals/StructuredContainers.md](Proposals/StructuredContainers.md) —
  seasonless series, serials, arcs and volumes, alternative cuts, in-band
  commentary tracks, and extras that belong to a story rather than to an
  episode. Uses Emby's own mechanisms where it has them and is invisible to it
  where it does not, so deleting every `.smd` leaves a working library behind.
- [Proposals/ContainerDatabase.md](Proposals/ContainerDatabase.md) — the same
  model as a shared store, keyed so that a disc fingerprint resolves to a
  container, its cuts and its commentaries. Sits above TheDiscDb, which
  identifies pressings, and duplicates none of it.
- [Proposals/Hosting.md](Proposals/Hosting.md) — how that store is kept and
  served: git as the source of truth, a build that bakes the data into the
  service it ships in, and a REST contribution path that keeps pull requests an
  implementation detail rather than a public interface.
- [Proposals/Roadmap.md](Proposals/Roadmap.md) — the order to build the three in,
  starting with a single-user tool that pressure-tests the schema against the
  awkward discs before any infrastructure exists to make changing it hard.

Both documents are written against Emby, because that is where the rules were
measured and because its constraints are what the format has to survive. Neither
is tied to it: the output is NFO sidecars and file layout, so Jellyfin, Kodi or
anything else that speaks the same convention reads the result, and a client that
knows about `.smd` reads the structure Emby cannot hold.

## Licence

Apache 2.0 — see [LICENSE](LICENSE). Every Markdown file carries an SPDX header
as an HTML comment, and `Scripts/check-license-headers.sh` enforces it in CI;
with nothing here to compile, that gate is the only thing that would ever notice
a file written without one.

The licence for the **data**, once there is any, is deliberately not settled
here: `ContainerDatabase.md` argues for CC BY 4.0 as the nearest analogue to
Apache's attribution requirement, with CC0 as the alternative if attribution
turns out to deter contributors. That choice belongs with the first row, not
with an empty repository.
