<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the smddb project authors -->

# Ingest

The phase 1 ingestion tool from `Proposals/Roadmap.md`, at its first step: a macOS window that does
what the MakeMKV GUI does — pick a drive or a folder, scan it, look at the titles and their streams,
tick the ones wanted, rip them — through [MakeMKVKit](../../../MakeMKVKit) rather than by hand.

Everything after that in the ingestion flow — fingerprint, identify, bind, write the `.smd` — is
not here yet. This exists so there is a working scan-and-rip loop to hang those steps off.

```sh
swift run Ingest
```

Three launch arguments exist for working on a screen without going through the ones before it:
`--scan N` scans drive N at startup, `--stage assign` opens on that stage, and `--seed-queue N`
puts N made-up files in the Assign queue.

The window is a sidebar of the workflow's stages and the selected stage's own view. **Import** is
the scan-and-rip loop; **Assign**, which says what each ripped file is, holds a queue that files
join one by one as Import finishes each of them, with the count badged on the sidebar. Assign is
currently the queue in a drawer and nothing else.

The Assign queue and the import history are kept in `~/Library/Application Support/smddb Ingest/state.json`,
rewritten whole on every change. A scanned disc is fingerprinted from its mounted volume the way
TheDiscDb keys discs, an MD5 over the stream file sizes and a SHA1 of `AACS/Unit_Key_RO.inf`, and
its history is filed under that hash; titles the history says were already imported come up
disabled and unticked, keyed by playlist, segment map and duration so a change of minimum length
does not lose them. A disc macOS cannot mount is filed under its MakeMKV name instead.

In Import, the opening screen is one button per drive; pressing one scans it. Drives and discs are noticed
as they come and go — a disc in or out through DiskArbitration, a drive plugged or unplugged
through IOKit — and the table is re-read from MakeMKV when they do. It is read again when the
window comes back to the front after a while, and on the way back from a scan, which covers the one
thing no event reports: a drive that went to sleep and woke up. File system events would not do for
any of this: an empty drive has nothing to watch. There is no refresh button; the empty state offers
"Look again", and that is the only manual re-read.

Needs MakeMKV installed at `/Applications/MakeMKV.app`, or `makemkvcon` on `PATH`. A source can be
a drive, a folder holding a `BDMV` or `VIDEO_TS` tree (a MakeMKV backup), or an `.iso`; the last two
work without a drive at all.

The library dependency is [MakeMKVKit](https://github.com/project-smd/MakeMKVKit), tracked by its
`main` branch until it has a release to pin to.
