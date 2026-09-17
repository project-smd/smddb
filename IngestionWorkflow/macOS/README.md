<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the smddb project authors -->

# Ingest

The phase 1 ingestion tool from `Proposals/Roadmap.md`, at its first step: a macOS window that does
what the MakeMKV GUI does — pick a drive or a folder, scan it, look at the titles and their streams,
tick the ones wanted, rip them — through [MakeMKVKit](../../../MakeMKVKit) rather than by hand.

Everything after that in the ingestion flow — fingerprint, identify, bind, write the `.smd` — is
not here yet. This exists so there is a working scan-and-rip loop to hang those steps off.

```sh
open "$(Scripts/build-app.sh)"
```

The script builds the package and wraps the executable as `Ingest.app` under `.build`, printing
the bundle's path. A bundle rather than `swift run` because the viewer plays through
[VLCKit](https://code.videolan.org/videolan/VLCKit), a dynamic framework that SwiftPM links but
does not put anywhere the executable can load it from; the bundle carries it in `Contents/Frameworks`.
The script also links the framework where SwiftPM's own products look for it, so after it has run
once, `swift test` and `swift run Ingest` work as well. `-c release` builds that configuration.

Four launch arguments exist for working on a screen without going through the ones before it:
`--scan N` scans drive N at startup, `--stage assign` opens on that stage, `--seed-queue N`
puts N made-up files in the Assign queue, and `--containers` opens the Containers window. Pass
them through `open` as `open "$(Scripts/build-app.sh)" --args --stage assign`.

The window is a sidebar of the workflow's stages and the selected stage's own view. **Import** is
the scan-and-rip loop; **Assign**, which says what each ripped file is, holds a queue that files
join one by one as Import finishes each of them, with the count badged on the sidebar. Selecting a
queued file opens it paused on its first frame, or playing if Playback in Settings says so: the
transport steps by chapter and by frame and the scrubber seeks as it is dragged, the file's chapters
are listed beside the facts MakeMKV recorded about the title it came from, and the audio and
subtitle menus switch tracks — which is how a commentary is told from the main mix. The video is
shown at its own shape, so black bars on screen are in the picture and never padding. Assigning
itself is not built yet.

**Containers**, under the View menu, is a window of its own onto the database: an outline of every
container in the repository, series at the top, and under each one four groups — its alternatives,
its features, its sequences and its extras — each opening to what it holds, with the selected
row's facts beside. A child container is an item of the sequence or the extras that hold it, and
opens the same way. Every group's header has a + that adds to the end of that group, and a
sequence's own + adds an item to it: an episode, a film or a featurette with a title, or a
container, whose type is guessed from the parent's, a season inside a series and a serial inside a
season. Dragging re-orders a group; ids are made from titles; the first alternative a container
gets is the one played by default. Add Container… in the toolbar makes one at the top level.
Selecting any row edits it beside the outline — a container's title, year and whether the year is
shown in the title, type, type label, outline, whether it is listed, which alternative plays by
default and where the extras are anchored; an alternative's, a feature's, a sequence's or an
item's own fields; and, on containers and items, as many external references as providers know
the thing, added and removed a row at a time. Nothing is written until Save (⌘S), and what would
not validate — a sequence id that is not a slug, an alternative playing a sequence that is not
there — is refused with the reason beneath the fields. Ids are shown and not edited, because other
rows name their targets by them; renaming a sequence renames it in the alternatives that play it.
That is the whole of authoring so far: nothing here is deleted once written apart from a reference
or a participant, bindings to discs are not made, and neither is a container built from a
provider's own record; those arrive with the identify and bind steps, which is when the discs say
what shape they need. The window reads
the repository folder chosen in Settings, and re-reads it each time the app comes to the front,
since the folder is a git clone and changes under the tool.

The container model, the file each container is kept as, and the repository behind them are
[SmdKit](../../SmdKit), a package beside this one that the tool depends on by path; its README
says what the files look like and why.

The Assign queue and the import history are kept in `~/Library/Application Support/smddb Ingest/state.json`,
rewritten whole on every change. A scanned disc is fingerprinted from its mounted volume the way
TheDiscDb keys discs, an MD5 over the stream file sizes and a SHA1 of `AACS/Unit_Key_RO.inf`, and
its history is filed under that hash; titles the history says were already imported come up
disabled and unticked, keyed by playlist, segment map and duration so a change of minimum length
does not lose them. A disc macOS cannot mount is filed under its MakeMKV name instead.

Assign has an action panel along the bottom, and the first action is Reject, for a file that has
been watched and is not worth keeping. It asks first, takes an optional description, deletes the
file, and turns the disc's record of the title from imported to rejected, so Import shows a red
"Rejected" and the date, and the title reads "Title 9 (description)". The button's menu refines
that to Reject as Disc Logo/Warning, where the description is required and the clip is remembered
apart from the disc: a title on any later disc with the same signature comes up rejected at scan
time, unticked, under that description, and is never imported. The signature is the title's exact
size in bytes, its duration, and the codec and shape of each primary stream. It cannot be a hash of
the bytes, which are encrypted per disc on the volume and carry a fresh UID and date in each MKV;
and it leaves out the file name, playlist, chapters and languages, which belong to the disc's
authoring rather than the clip. A rejection is taken back from the title's context menu in Import,
which for a disc logo forgets the clip as one.

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

The library dependencies are [MakeMKVKit](https://github.com/project-smd/MakeMKVKit), tracked by
its `main` branch until it has a release to pin to, and VLCKit, pinned to an exact 4.0 prerelease
tag because that line is still alpha. VLCKit is LGPL 2.1 and is used as a framework, unmodified.
