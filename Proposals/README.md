<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the smddb project authors -->

# Proposals

Designs argued before they are built. Nothing in here is implemented; when a
proposal lands, its content becomes the specification and the code, and the
document stays as the record of what was decided and why.

- [Structured Containers](StructuredContainers.md) — a sidecar format for series
  structure Emby has no shape for: seasonless series, serials, arcs and volumes,
  alternative cuts, and in-band tracks. Uses Emby's own mechanisms where it has
  them, and is invisible to it where it does not.
- [Container Database](ContainerDatabase.md) — a shared store of the same model,
  keyed so that a disc fingerprint resolves to a container, its cuts and its
  commentaries, and an `.smd` can be generated at ingestion instead of typed.
  Sits above TheDiscDb, which identifies pressings, and never duplicates it.
- [Roadmap](Roadmap.md) — the order to build the other three in, what each
  phase has to prove before the next starts, and the decisions that are not
  urgent yet but have a deadline.
- [Hosting](Hosting.md) — git as the store, a build that bakes the data into
  the service, and a REST contribution path that keeps the review mechanism an
  implementation detail. Decides the licence and provenance questions the
  database proposal leaves open.
