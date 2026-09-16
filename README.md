<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the smddb project authors -->

# smddb

Two designs for the same model: `.smd`, a sidecar format describing series
structure that Emby's three fixed levels cannot hold, and the shared database
behind it, which knows what a container is and which pressing of which disc
holds each piece of it.

The proposals are the argument, and the two design documents are meant to be
read in order — the database mirrors the sidecar one to one, so the format
settles the vocabulary the schema then uses. Phase 1 of the roadmap is under
way beside them:

- [SmdKit](SmdKit) — the container model, the file each container is kept as
  in the data repository, and the database interface over a folder of them.
  Nothing Apple-only, so it builds wherever Swift does and CI tests it.
- [IngestionWorkflow/macOS](IngestionWorkflow/macOS) — the phase 1 tool: scans
  a disc through MakeMKV, rips the titles wanted, and is growing the steps
  after that.

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

Apache 2.0 — see [LICENSE](LICENSE). Every Markdown and Swift file carries an
SPDX header, and `Scripts/check-license-headers.sh` enforces it in CI; nothing
in the toolchain would otherwise notice a file written without one.

The **data** lives in its own repository, [project-smd/data](https://github.com/project-smd/data),
and is dedicated to the public domain under CC0 1.0. The grounds are in the
licence section of `ContainerDatabase.md`; the contribution rules, facts from
anywhere and prose of your own, are in that repository's `CONTRIBUTING.md`.
