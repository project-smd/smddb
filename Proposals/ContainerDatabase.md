<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the smddb project authors -->

# Container Database

**Status:** proposal. Nothing here is implemented. Depends on
`StructuredContainers.md`, whose `.smd` format this database mirrors one to one.

A shared database that knows what a container *is* — a serial, its parts, its
cuts, its commentaries, the extras that belong to it — and which pressing of
which disc holds which piece of it. Given a MakeMKV log, it should be able to
say "this is Season 14 Disc 3 of the 2018 Blu-ray, playlist 00117 is part 4 in
the broadcast cut, and audio stream 3 is the first commentary", and from that an
`.smd` can be generated rather than typed.

## The problem

The `.smd` is a semantic layer, and it is hand-authored per library. Every
person who rips the same disc re-derives the same facts: which playlists are
episodes, which are the play-all pseudo-title, which audio stream is the
commentary, and what the whole thing is a season of. CDDB solved this for audio
CDs thirty years ago by keying a shared store on a cheap fingerprint of the
disc. Nothing equivalent covers video, and the reason is not the fingerprint.

What exists, measured in September 2026:

- **TheDiscDb** (thediscdb.com, data MIT-licensed on GitHub) is the
  identification half, and it is real: 1,745 movie releases, 336 series
  releases, 5,117 discs, updated daily, with an unauthenticated GraphQL
  endpoint. Each disc is keyed by the AACS disc id and by a content hash over
  the stream files' names, sizes and timestamps, both derivable from the MakeMKV
  log. Each playlist carries the MakeMKV facts — duration, segment map, size,
  per-stream codec and language — and, where a contributor has bothered, a
  label: a type from a short list and a season and episode number.
- **Its semantic layer is one table with five fields.** Of fourteen object
  types in its schema, one carries meaning. 15% of playlists are labelled, 4%
  of those have a description, and 0.2% of audio and subtitle streams have a
  role. Episode identity is the series' TMDb id plus two contributor-typed
  numbers, unchecked: a live Stranger Things disc labels season 1 episode 3 as
  season 2 episode 3, with the title of the former and the numbering of the
  latter.
- **TMDb, TVDB and Wikidata** hold episode identities, and for some shows an
  order: TMDb has a "Story Order" episode group for classic *Doctor Who*, and
  Wikidata has each serial as an item with its parts. None models cuts,
  in-band features, or extras filed against a story.
- **mkv-episode-matcher, Engram and FileBot** identify episodes from content or
  from order, and re-derive the answer on every run.

So the disc-fingerprint problem is solved, the episode-identity problem is
solved, and the thing in between — what a container is and how a pressing maps
onto it — is held nowhere. That layer is the `.smd`, and this proposal is the
shared store for it.

## Principles

1. **The semantic layer is the product; disc data is for matching only.**
   Nobody wants to know that part 5 on disc 2 has six segments, except the code
   deciding which playlist to rip. Playlist facts are stored to the extent
   needed to identify a playlist and no further. TheDiscDb already keeps the
   rest.
2. **The database and the `.smd` are the same model.** Every table here is an
   element in `StructuredContainers.md`, and every rule there is a constraint
   here. An `.smd` is what a client gets when it asks for one container; the
   database is what it asks. Nothing is expressible in one and not the other,
   except the bindings to pressings, which the `.smd` does not need.
3. **Identity is minted here and never reissued.** A container, a sequence, an
   entry, an alternative and a feature each have an id that two people with
   different pressings resolve to. TVDB, TMDb and the rest are attached as
   external references, as many per entity as there are providers that know
   it, and are never primary keys, because an extra has no external id and an
   omnibus cut usually has none either. This is what MusicBrainz's
   MBIDs are, and it is the difference between a database and a schema.
4. **TheDiscDb is a hint, not a fact.** Its disc keys are reused unchanged so a
   lookup there and a lookup here answer the same question about the same
   disc. Its episode labels are checked against the provider before they are
   believed, and a disagreement is reported rather than resolved silently, on
   the principle the sidecar proposal applies throughout: a conflict between two
   sources is shown and labelled, never quietly decided.
5. **Provenance is recorded at ingestion, because it cannot be recovered
   afterwards.** A binding says which disc and which playlist a file came from.
   That is what lets a correction go back upstream, and what makes a second
   copy of the same disc bind to the same entries without anyone typing.

## Data model

Named for the `.smd` element each mirrors. Types are indicative; the keys are
the design.

```
Container      ContainerId, ParentEntryId (null at the root), Listed,
               Type (series|season|serial|arc|volume|collection|episode|movie),
               TypeLabel, Title, Outline

Sequence       SequenceId, ContainerId, Exploded (never|allowed|preferred)

Alternative    AlternativeId, ContainerId, SequenceId, Key, Title, Outline,
               IsDefault

Feature        FeatureId, ContainerId, Type (commentary|isolatedMusic|…), Title

Person         PersonId, Name

Participation  EntityKind (feature|entry), EntityId, EntryId (nullable),
               PersonId, Position, Role

Entry          EntryId, SequenceId, Position, Role (sequence|extra),
               Optional, Type (episode|movie|container|featurette|…),
               ChildContainerId (when Type = container),
               RefEntryId (when the entry is a ref; any container),
               Title, Outline (only when the entry has no ExternalRef)

Relation       ContainerId, RelatedContainerId, Role (companion|…)

Release        ReleaseId, Title ("The Collection: Season 14"), Region,
               ReleaseDate

Disc           DiscId, DiscFingerprint (AACS disc id + content hash),
               Format (DVD|Blu-ray|UHD)

ReleaseDisc    ReleaseId, DiscId, Index, Label ("Season 14 Disc 3")

ExternalRef    EntityKind (container|entry|release|disc|feature|person),
               EntityId, Provider, Value
               unique on (Provider, Value, EntityKind)

DiscTitle      DiscTitleId, DiscId, Playlist, SegmentMap, Duration
               -- exists only while at least one Binding points at it

Chapter        DiscTitleId, Index, Title

Binding        BindingId, DiscTitleId, EntryId, AlternativeId (nullable),
               ChapterFrom, ChapterTo (nullable), ContributorId, Recorded

BindingStream  BindingId, FeatureId, AudioIndex, SubtitleIndex (nullable)
```

A DiscTitle row is not a catalogue of the disc. It exists because a binding
needs something to hang off, and it is deleted when the last binding is. A
looping menu, a studio logo, a copyright card and the play-all pseudo-title are
never rows here; TheDiscDb records them, and the ingestion flow uses that
record to skip them. This is not a MakeMKV dump, and the constraint is what
keeps it from becoming one.

Chapter titles belong to the disc title rather than to the binding, because
they are a fact about the playlist whichever entry it is bound to; a binding
with a chapter span sees its slice of them.

A Release is the box: the thing with a barcode, a region and a date, that a
person buys and that TheDiscDb, Amazon and DVDCompare each have a page for. A
Disc is the pressing inside it, identified by fingerprint and nothing else;
format sits on the disc rather than the release because a box mixes them —
*The Daleks in Colour* is one Blu-ray and one DVD in the same case. The
junction between them carries the disc's index and label *within that box*,
because the same physical disc turns up in more than one box — a standalone
release and a later collection — and is "Disc 1" in one and "Disc 7" in the
other. A UPC, an ASIN, an EAN and a TheDiscDb release slug are external
references to the Release; a disc has no external identity but its
fingerprint. What a release is a release *of* is not stored: it follows from
what its discs are bound to, and storing it would be a second source of truth
for a fact the bindings already carry.

A commentary is mostly interesting for who is on it, and an interview or a
featurette has the same property, so participation is a junction that a
Feature or an Entry can own: one row per person, in credited order, with the
role the person has to the programme. `EntryId` is normally null, meaning the
person is on that feature throughout; a row that sets it overrides the line-up
for one part, which is what a commentary whose participants change between
episodes of a story requires. A feature is one thing when it is one listening
experience, so its participants are a property of the run rather than of a
recording session, and they are allowed to vary along it. People are their own table so that the
same director on twelve commentaries is one row with one set of provider ids —
TMDb, IMDb and Wikidata all identify people — rather than twelve name strings
that may or may not be spelled alike. A feature may carry external references
of its own too, for the rare case where a provider has an entry for the
commentary itself; nothing depends on it.

External identity is a table rather than a column, because one column would be
wrong three ways. The same episode has ids at TVDB, TMDb, IMDb and Wikidata, and
the ingestion flow arrives with a TMDb hint from TheDiscDb while the NFO is
written with a TVDB id, so an entry has to carry both. Containers and discs need
the same thing — a series has two provider ids, a serial has a Wikidata item, a
release has a UPC, an ASIN and a TheDiscDb release slug — and one table serves
all four kinds. And providers disagree about what an episode is, splitting and
merging double-length episodes differently, so an entry carries a ref from
every provider whose unit matches it and omits the ones whose unit does not,
rather than being forced to choose. The uniqueness constraint is what makes a
provider id a lookup key: one TVDB episode id resolves to at most one entry.

How the two halves correspond:

| `.smd` | Table | Notes |
| --- | --- | --- |
| `<container>` | Container | `nfo` pointer has no counterpart; descriptive fields are present here whether or not Emby has an item, and the `.smd` writer omits them when it does |
| provider ids in the NFO | ExternalRef | The `.smd` never carries them; the NFO does, and the writer takes them from here |
| `<sequence id>` | Sequence | An unnamed sequence is a Sequence that no Alternative names |
| `<alternative sequence>` | Alternative | The foreign key runs from alternative to sequence, as the attribute does |
| `<feature>` | Feature | |
| `<participant name role>` | Participation → Person, EntryId null | The `.smd` carries name and role, as an NFO does; the provider ids for the person are here |
| `<participant>` under a `<track>` | Participation with EntryId set | Overrides the feature's default line-up for that one part, which is what a commentary whose participants rotate between episodes needs |
| `listed` | Container.Listed | False for a companion series nobody browses to directly, such as *Behind the Sofa* |
| `<item>` in `<sequence>` | Entry, Role = sequence | Position is document order |
| `<item>` in `<extras>` | Entry, Role = extra | The `anchor` is a projection detail and is not stored |
| `<item ref>` | Entry with RefEntryId | No title, no bindings, no children; the target may be in any container, which is how a companion series' episode appears in another series' extras and how extras scattered across a box set form a series of their own |
| `<related container role>` | Relation | Season-to-season pairing for a companion series; per-item pairing by position is derived from it and an authored ref wins |
| `<presentation>` | *none* | A presentation is a local file; a Binding is where it came from |
| `<presentation alternative>` | Binding.AlternativeId | |
| `<source disc playlist>` | DiscTitle, by natural key | The `.smd` names the disc's content hash and the playlist, never a DiscTitleId, so a hand-edited file stays self-describing |
| `<chapter index title>` | Chapter | The tool writes them into the ripped file as well; the `.smd` declares them because it writes them |
| `<track feature audio subtitle>` | BindingStream | Indices are the disc playlist's, not the ripped file's; a remux renumbers and the verification pass in the sidecar proposal already covers that |

The one deliberate asymmetry is `profile`. A mobile re-encode is a fact about a
library, not about a pressing, so it lives in the `.smd` and has no table. The
database describes what a disc holds; the sidecar also describes what was made
from it.

### Resolution rules

The alternative a binding realises is resolved in two steps: the binding's own
`AlternativeId` if set, otherwise every alternative that names the entry's
sequence. So:

- A binding on the omnibus entry with a null alternative serves every
  omnibus-shaped alternative, by the same rule that a binding on broadcast
  part 1 with a null alternative serves `broadcast` and `se`.
- A binding that does name an alternative must name one whose `SequenceId` is
  the entry's. That is the only cross-table check the model needs, and it is
  the database form of "a qualified presentation must name an alternative on
  its own sequence".
- A ref entry carries no bindings. Resolving one follows `RefEntryId` and then
  applies the two steps to the target. The target may be in another container:
  *Doctor Who Confidential* episodes have their home in their own series, with
  a TVDB id, and a *Doctor Who* episode's extras hold a ref to one; *Behind the
  Sofa* instalments have their home in each story's extras, and a container of
  their own holds refs to them. The rule for which side is home: an entry with
  a provider identity lives in that provider's series, and one without lives
  where its file is filed.

Chapter spans cover a DVD title that holds several episodes — TheDiscDb records
these as "Episode: 5-11" — as several bindings from one DiscTitle, each to its
own entry with a chapter range. The other direction, one entry across several
titles, is a multi-file presentation and is out of scope here as it is in the
sidecar proposal.

### Identity keys

Two of the keys are borrowed deliberately, so that lookups interoperate:

- **DiscFingerprint** is TheDiscDb's pair — the AACS disc id (`GlobalDiscId`)
  and its content hash — unchanged. A MakeMKV log that identifies a disc there
  identifies it here, and a miss here can fall back to a hit there.
- **A Release is found by its external references**, UPC first, and a
  TheDiscDb release slug where one exists, so that a release catalogued there
  and a release catalogued here are recognisably the same box.
- **DiscTitle** is keyed by playlist name plus segment map plus duration, never
  by MakeMKV's title index. The index shifts with the minimum-length setting
  and across MakeMKV versions; the playlist does not.

Everything else — ContainerId, SequenceId, EntryId, AlternativeId, FeatureId —
is minted here. A UUID is fine; what matters is that it is issued once and the
same one comes back tomorrow.

## Worked example

*The Talons of Weng-Chiang* as a serial with a broadcast cut, an
effects-updated cut and an omnibus, bound to two discs. Ids abbreviated.

```
Container    C1   serial  "The Talons of Weng-Chiang"

Sequence     S1   C1                       -- six parts
Sequence     S2   C1                       -- one film

Alternative  A1   C1  S1  broadcast  default
Alternative  A2   C1  S1  se
Alternative  A3   C1  S2  omnibus

Feature      F1   C1  commentary  "Commentary — Jameson, Bennett, Barry"

Person       P1   "Louise Jameson"      ExternalRef  person P1  tmdb  …
Person       P2   "John Bennett"        ExternalRef  person P2  tmdb  …
Person       P3   "Christopher Barry"   ExternalRef  person P3  tmdb  …
Participation  feature F1  P1  pos 1  "Leela"
Participation  feature F1  P2  pos 2  "Li H'sen Chang"
Participation  feature F1  P3  pos 3  "Director"

Entry        E1   S1  pos 1  episode  (part 1)
Entry        E2   S1  pos 2  episode  (part 2)
…
Entry        E7   S2  pos 1  episode  "Omnibus edition"   -- no provider knows it
Entry        E8   S1  extra  featurette  "Now and Then"

ExternalRef  container C1  wikidata  Q3475469
ExternalRef  entry E1      tvdb      1234
ExternalRef  entry E1      tmdb      5678
ExternalRef  entry E2      tvdb      1235
…

Release      R1   "The Collection: Season 14"   region B   2018
ExternalRef  release R1  upc  …
ExternalRef  release R1  asin  …
ExternalRef  release R1  thediscdb  <release slug>

Disc         D1   AACS …, hash …   Blu-ray
Disc         D2   AACS …, hash …   Blu-ray
ReleaseDisc  R1  D1  index 3  "Season 14 Disc 3"
ReleaseDisc  R1  D2  index 4  "Season 14 Disc 4"

DiscTitle    T1   D1  00117.mpls  seg 45      1:15:20
DiscTitle    T2   D2  00004.mpls  seg 12      0:24:40
DiscTitle    T3   D2  00005.mpls  seg 13      0:24:40
DiscTitle    T4   D2  00289.mpls  seg 281     0:11:36

Binding      B1   T1 → E7   alt null            -- omnibus, serves A3
Binding      B2   T2 → E1   alt null            -- part 1, serves A1 and A2
Binding      B3   T3 → E1   alt A2              -- part 1, effects-updated only
Binding      B4   T4 → E8   alt null            -- the featurette

BindingStream B2  F1  audio 3
BindingStream B3  F1  audio 3
```

A client holding disc D2's log fingerprints it, finds D1 and D2 both belong to
C1's bindings, and can write the serial's `.smd` with every presentation and
track mapping filled in, leaving only local facts — file paths, the mobile
profile — to the tool. *The Daleks in Colour* is the same shape with real data:
one Blu-ray playlist bound to a single entry in an omnibus sequence, and a DVD
whose seven titles bind, out of disc order, to the seven parts.

## Questions the model answers

The test of a schema is the questions it can be asked. Each of these is a join
along the tables above, and the last two are the ones no existing store can
answer at all.

| Question | Path |
| --- | --- |
| What is on this disc? | Disc → DiscTitle → Binding → Entry → Sequence → Container. The ingestion lookup. |
| Which discs carry this entry? | Entry → Binding → DiscTitle → Disc. Each row on the way also says the playlist, the alternative served, and a chapter span if the entry is a slice of a longer title. |
| Which discs carry this entry *in this cut*? | The same, filtered to bindings whose alternative is the one asked for or null on a sequence it names. The resolution rule used as a predicate. |
| Which discs carry this feature? | Feature → BindingStream → Binding → DiscTitle → Disc, with the audio and subtitle stream index on each. |
| Every commentary this person recorded, and where? | Person → Participation → Feature, then the row above. Interviews and featurettes come the same way through Entry. |
| Which *parts* was this person actually on? | The same, reading Participation.EntryId — null means every part of the feature, set means that one. Unanswerable before participation could vary within a commentary. |
| What companion series does this one have? | Relation by role, ignoring Listed — which is the point of the flag: unlisted containers are reachable here and nowhere else. |
| Which cuts of this container exist, and which discs hold each? | Container → Alternative → Sequence → Entry → Binding → DiscTitle → Disc. |
| What is this thing an extra *of*? | Entry (Role = extra) → Sequence → Container, and up ParentEntryId to the series. |
| What is this episode *about*, or what is about it? | Relation between containers, or a ref from one container's extras into another's sequence, in either direction. |
| Which pressings are the same physical disc? | Disc, by fingerprint. Two boxes sharing a master share the row. |
| Which boxes can I buy this entry in? | Entry → Binding → DiscTitle → Disc → ReleaseDisc → Release, and out through the release's ASIN or UPC. |
| What is this box a release of? | Release → ReleaseDisc → Disc → DiscTitle → Binding → Entry → Container. Derived, never stored. |
| Where did this file come from? | `<source>` in the `.smd` → DiscTitle by natural key → Disc, and from there to every other library that bound the same pressing. |

Three qualifications, none of them gaps.

- **A ref entry has no bindings of its own.** Asking any of these of a ref means
  following `RefEntryId` first. Asking them of *Behind the Sofa* as a container
  means asking them of each ref's target, which is the right answer: those
  discs are where the instalments physically are.
- **Every answer is "among the discs someone has bound", not "among the discs
  that exist".** A pressing nobody has ingested is invisible. That is the CDDB
  property, and it is why the contribute step in the flow below is not
  optional.
- **The feature question is the one worth noticing.** TheDiscDb can say a disc
  has a stream someone described as "Commentary". It cannot say which discs
  carry *a particular* commentary, because there is no entity for the
  commentary to be. Here there is, and the question is one join longer than
  the entry question.

## Ingestion flow

The flow the database exists to serve, from a disc in a drive to a library
Emby can read:

1. **Scan.** Run MakeMKV's robot info against the disc and keep the log; that
   is the same log TheDiscDb takes, so it serves both.
2. **Identify the disc.** Compute the fingerprint and look it up here; a hit
   gives the disc, every release it ships in, and its bindings. On a miss,
   look it up on TheDiscDb; a hit there gives the release — which is created
   here with its UPC and slug as external references — and, for labelled
   playlists, a season and episode hint.
3. **Identify the container.** Resolve the series through its TMDb or TVDB id
   to its root container here. Where none exists, the container has to be
   authored — the one step that is genuinely human — with TMDb episode groups
   and Wikidata as a starting shape where they have one.
4. **Bind.** With both known, every playlist that has a binding maps to an
   entry and an alternative, and every labelled stream to a feature. Playlists
   with no binding are presented for labelling with TheDiscDb's hint, if any,
   pre-filled and checked against the provider's runtime and title.
5. **Rip and write.** Rip the bound playlists, name the files by the sidecar
   proposal's rule, write chapter names into each file, and emit the `.smd`
   with presentations, track maps, chapters and a `<source>` naming the disc
   and playlist each file came from.
6. **Contribute.** New bindings and labels go back to the database. Labels that
   TheDiscDb lacks can be submitted there too, in its summary format, which
   already accepts a per-stream role.

Steps 2 and 3 are lookups. Step 4 is where the network effect lives: the first
person to bind a pressing does the work, and everyone after them with the same
pressing gets an `.smd` for free.

## Hosting and licence

Sketched here and argued in full in `Hosting.md`, which supersedes this section
on everything except the licence question below.

An open-source project: the code on GitHub under Apache 2.0, as this repository
is, and the data under a licence of the same temper. The nearest data-licence
analogue to Apache's attribution requirement is CC BY 4.0, which asks for
credit and nothing else; CC0 is the alternative if attribution turns out to
deter contributors, and is what MusicBrainz chose for its core data. Either
way the data is exported wholesale and regularly, because a store whose only
copy is the one being served is a store that can disappear — TheDiscDb's MIT
data repository is the right precedent.

## Region variants

A region variant is a different release, and almost always a different disc.
The release has its own barcode and its own row; the disc has its own
fingerprint, its own titles and its own bindings, and nothing about the region
1 pressing transfers to the region 2 one except by someone binding it. That is the honest position:
TheDiscDb is 90% region 1, a UK library will mostly be binding pressings nobody
has seen, and pretending two masters are one would make the first mismatch a
silent one. Where two pressings genuinely share a disc — the same physical
master in two boxes — they share a Disc row, because the fingerprint says so.

## Non-goals

- **Not a replacement for TheDiscDb, and not a MakeMKV dump.** A playlist is
  a row here only because something is bound to it. Menus, logos, warnings and
  play-all titles are never recorded; TheDiscDb catalogues them, and
  duplicating its 258,880 playlist rows would be the wrong kind of
  completeness.
- **Not a metadata database.** Cast, ratings, plots and air dates stay with the
  providers, exactly as the sidecar proposal keeps them in the NFO. An entry
  carries a title only when no provider has one for it.
- **Not a ripping tool.** The flow above is what a tool does with the database;
  the database does not scan discs.
- **Not a graph.** One home per entry, as in the sidecar; a ref, including one
  into another container, is a position, not a second home. Relation carries
  container-level pairings and nothing else.

## Open questions

1. **Whether to contribute upward instead.** TheDiscDb's `DiscItemReference` is
   the seam where a pointer into a richer entity would go. A conversation with
   its maintainer about carrying an EntryId there might remove the need for a
   separate Disc and DiscTitle table entirely, leaving this database purely
   semantic. Worth having before building the identification half twice.
2. **Chapters inside an omnibus.** Chapter *titles* are now stored; a chapter
   *map* from an omnibus back onto the parts sequence is still deferred, for
   the reason given in the sidecar proposal. The Chapter and Binding tables
   have room for it when it is wanted.
