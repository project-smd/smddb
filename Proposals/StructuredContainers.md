<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the smddb project authors -->

# Structured Containers

**Status:** proposal. Nothing here is implemented.

A sidecar format — `.smd`, *structured media description* — that describes the
structure Emby's data model cannot hold, while leaving the folder layout and the
NFO sidecars exactly as Emby wants them. Emby keeps reading the library it
already understands, and gets a slightly better one out of the arrangement; a
container-aware client reads the same library and sees the shape that is
actually there.

## The problem

Emby's model is three levels deep and fixed: series, season, episode. Everything
else has to be lied about.

- **A series with no seasons.** Anthologies, mini-series, and anything released
  as a flat run get folded into a phantom `Season 1` because there is nowhere
  else to put them.
- **A series or season split into serials, arcs or volumes.** Classic *Doctor
  Who* is 26 seasons of six-part serials; the serial is the unit a person
  watches and names, and Emby has no level for it. The same problem shows up as
  arcs in a procedural, volumes in an anime release, and books in a
  literary adaptation.
- **Alternative cuts.** A broadcast version and an updated-effects version are
  the same story. Emby can hold them — episodes support multiple versions — but
  it labels them from the filename and has nowhere to say what either one *is*.
- **In-band alternates.** A commentary track or an isolated music track is a
  distinct thing to watch, described nowhere, discoverable only by opening the
  audio menu and guessing from a language code.
- **Structural extras.** A featurette about a serial belongs to the serial, not
  to any one of its six parts and not to the season. Emby offers three places to
  file it and renders two of them as episodes.

There is one lever Emby leaves open: **identity numbering and display numbering
are separate**, and Emby's parser honours
`<displayseason>`/`<displayepisode>` on any episode, not just specials. That is
enough to reorder a flat list. It is not enough to express a tree. This proposal
adds the tree beside the library rather than inside it, and keeps display
numbering as the projection of that tree onto what Emby can render.

## What Emby actually does

Measured against a running server, September 2026. The
[TV naming article](https://emby.media/support/articles/TV-Naming.html) covers
where files may be put and not what happens once they are there, and on one
point below the observed behaviour contradicts it. The design that follows rests
on these four facts, so if any of them changes the design should be revisited
rather than patched.

**Extras folders are recognised at all three levels, and each level renders
differently.** The nine names — `extras`, `specials`, `shorts`, `scenes`,
`featurettes`, `behind the scenes`, `deleted scenes`, `interviews`, `trailers` —
are accepted under the series, under a season, and inside an episode folder. What
they do there is not the same:

| Filed under | What Emby does with it |
| --- | --- |
| The series | Merges it into the **Specials** season, among the real season-0 episodes |
| A season | Appends it to the **end of that season**, as though it were a late episode |
| An episode folder (`S14E21/`) | Shows it in an **Extras row** on that episode's page |

Only the third is an extras row. The first two present an extra as an episode,
which is most of the reason this format exists.

**Extras carry metadata after all.** An extra's NFO and thumb are consulted at
every level. The naming documentation says nothing about it, and the common
belief — that an extra is a filename with a type attached, and the filename is
the on-screen title — is wrong.

**An episode-level extra's NFO is rooted at `<movie>`,** not `<episodedetails>`,
even though the thing it describes is filed under an episode of a TV series. It
is an inconsistency in Emby rather than a rule with a reason behind it, but it is
the rule, and a writer that emits `<episodedetails>` there produces a file Emby
ignores.

**Episodes support multiple versions.** The documented convention is two files
differing only after a dash — `Star Trek, The Next Generation - S01E01 - Original
Broadcast.mkv` beside `… - S01E01 - Digital Remix.mkv` — and the article states
that "anything following the '-' (dash) up to the file extension will be used in
the drop down version selector". Observed, the selector shows the **entire
filename**, not the trailing segment. The capability is real and usable; the
label is not what the documentation promises, which is the sort of thing this
project prefers to encode from behaviour rather than from prose.

**A version group has one set of metadata, taken from the first NFO,** and the
grouping survives being inside an episode folder that also holds extras folders —
so the anchor item can have its versions and its extras row at once, which the
documented examples show only separately. "First" is doing a lot of work in that
sentence, and it is not established whether it means first by filename, by
directory order, or by scan order. The design below refuses to depend on the
answer: every sidecar in a group is tracked and kept in agreement, so whichever
one Emby reads is the right one.

## Principles

1. **Emby must see a correct library, not a confused one.** Where Emby has a
   mechanism for something — extras folders, multi-version episodes — the layout
   uses it, and the `.smd` records what Emby's version of it leaves out. Where
   Emby has nothing, the `.smd` carries the whole fact and Emby is none the
   wiser. Deleting every `.smd` in a library leaves a working Emby library
   behind, which is also the rollback plan.
2. **The container tree is not the folder tree.** Emby and the metadata
   providers want a `Season 01/` folder and a `season.nfo`, so the library has
   them. That obliges the containers to nothing. A level is modelled where it is
   real and skipped where it is not, and a series that has no seasons simply has
   episodes in its sequence — the folder they happen to sit in is a path, not a
   parent. Copying Emby's shape into the `.smd` would reproduce the thing the
   format exists to get away from.
3. **One source of truth per fact.** Where a container corresponds to an item
   Emby already has — a series, a season, an episode — its descriptive metadata
   stays in the NFO and the `.smd` does not repeat it. A container carries title
   and plot only when Emby has no item to hold them.
4. **Discovered where the tool reads, declared where the tool writes.** A thumb,
   a `.bif` and a subtitle are never listed: they follow from a stem by rules the
   scanner already implements, and listing them would create a second source of
   truth that goes stale the first time a file is renamed. An NFO is listed,
   because the tool writes it. Every file the tool will modify is named in the
   `.smd` at the level it belongs to, so the set of write targets is auditable
   before an apply rather than inferred during one.
5. **Structure is a tree, not a graph.** Every item has exactly one home
   container. A thing that appears in two places is a hard problem for player
   state, resume points and "next up", and v1 declines it.
6. **Order is authored by position, not by number.** Document order inside a
   container is the order. Numbers are derived when projecting onto Emby, never
   hand-maintained in two places.

## Shape of the format

One container per file, XML, rooted at `<container>`:

```xml
<container format="1" type="serial" id="talons-of-weng-chiang">
  <!-- No nfo attribute: Emby has no item for a serial, so the fields below
       exist nowhere else. -->
  <title>The Talons of Weng-Chiang</title>
  <typeLabel>Story</typeLabel>
  <outline>Fog-bound Victorian London, a stage magician, and a war criminal
           from the fifty-first century.</outline>

  <!-- Two of these share the six-part shape and differ only in which
       presentation each part uses. The omnibus is a different shape — one
       film — so it names a sequence of its own. -->
  <alternatives default="broadcast">
    <alternative id="broadcast" sequence="parts">
      <title>Broadcast version</title>
      <outline>As transmitted, February–April 1977.</outline>
    </alternative>
    <alternative id="se" sequence="parts">
      <title>Updated special effects</title>
      <outline>2010 DVD release with re-composited effects shots.</outline>
    </alternative>
    <alternative id="omnibus" sequence="omnibus">
      <title>Omnibus edition</title>
      <outline>The six parts edited into one feature-length film.</outline>
    </alternative>
  </alternatives>

  <features>
    <feature id="commentary1" type="commentary">
      <title>Commentary — Louise Jameson, John Bennett, Christopher Barry</title>
      <participant name="Louise Jameson" role="Leela"/>
      <participant name="John Bennett" role="Li H'sen Chang"/>
      <participant name="Christopher Barry" role="Director"/>
    </feature>
    <feature id="music1" type="isolatedMusic">
      <title>Isolated music track</title>
    </feature>
  </features>

  <sequence id="parts">
    <item type="episode" id="prequel" optional="true">
      <presentation nfo="Doctor Who (1963) - s14e042 - The Talons of Weng-Chiang Prequel.nfo"
                    file="Doctor Who (1963) - s14e042 - The Talons of Weng-Chiang Prequel.mp4"/>
    </item>

    <item type="episode" id="part1">
      <presentation nfo="S14E21/Doctor Who (1963) - s14e021 - The Talons of Weng-Chiang Part 1 - Broadcast version.nfo"
                    file="S14E21/Doctor Who (1963) - s14e021 - The Talons of Weng-Chiang Part 1 - Broadcast version.mkv">
        <source disc="3F1A…C2E9" playlist="00004.mpls"/>
        <track feature="commentary1" audio="3"/>
        <track feature="music1" audio="4"/>
        <chapter index="1" title="Opening titles"/>
        <chapter index="2" title="Fog on the Thames"/>
      </presentation>
      <presentation profile="mobile"
                    nfo="S14E21/Doctor Who (1963) - s14e021 - The Talons of Weng-Chiang Part 1 - Mobile.nfo"
                    file="S14E21/Doctor Who (1963) - s14e021 - The Talons of Weng-Chiang Part 1 - Mobile.mkv">
        <track feature="commentary1" audio="2"/>
      </presentation>
      <presentation alternative="se"
                    nfo="S14E21/Doctor Who (1963) - s14e021 - The Talons of Weng-Chiang Part 1 - Updated special effects.nfo"
                    file="S14E21/Doctor Who (1963) - s14e021 - The Talons of Weng-Chiang Part 1 - Updated special effects.mkv"/>
    </item>

    <!-- Parts 2–6 follow the same pattern. -->
  </sequence>

  <!-- One item, one file. It is named as a version of part 1 because that is
       how the projection hands it to Emby; see "Projection". -->
  <sequence id="omnibus">
    <item type="episode" id="omnibus-feature">
      <presentation nfo="S14E21/Doctor Who (1963) - s14e021 - The Talons of Weng-Chiang Part 1 - Omnibus edition.nfo"
                    file="S14E21/Doctor Who (1963) - s14e021 - The Talons of Weng-Chiang Part 1 - Omnibus edition.mkv"/>
    </item>
  </sequence>

  <extras anchor="part1">
    <item type="featurette" id="now-and-then">
      <presentation nfo="S14E21/featurettes/Doctor Who (1963) - The Talons of Weng-Chiang - Now and Then.nfo"
                    file="S14E21/featurettes/Doctor Who (1963) - The Talons of Weng-Chiang - Now and Then.mkv"/>
    </item>
  </extras>
</container>
```

Read against the sketch this came from, the differences are the argument, so
they are each set out below.

### `<container>` declares what it is

`type` is one of `series`, `season`, `serial`, `arc`, `volume`, `collection`,
`episode`, `movie`. The sketch encoded the type in the filename ("serial
container"), which cannot be validated and cannot be read without a naming
convention that would then also need documenting.

`typeLabel` is the on-screen noun, because shows disagree about it: *Doctor
Who* says **Story**, an anime release says **Volume**, a procedural says
**Arc**. The parser branches on `type`; the UI prints `typeLabel`.

`<year>` is the year a series began, a season aired or a film was released,
and only those three types carry one: a serial or an episode takes its year
from its season, and a collection has none. `inTitle="true"` on it says the
year is part of the name — *Doctor Who (1963)* against *Doctor Who* — which is
how a library folder and Emby's own naming tell the 1963 programme from the
2005 one. The title element holds the title alone either way, so a client that
wants the bare name has it without parsing brackets out of a string.

`format="1"` is present from the first file written. A format that will be
extended and has no version marker cannot be extended safely, and adding the
marker later means every file predating it is ambiguous.

`id` is unique within its parent and is what the projection's journal, the
resume state and any cross-file reference name. Filenames are not identity: the
whole point of the editing tool is that files move.

`listed="false"` keeps a container out of a listing of everything, leaving it
reachable only through the relations that point at it. *Behind the Sofa* is a
programme with a series container and season containers like any other, but it
is not something anyone browses to from the top of a library — you arrive at it
from *Doctor Who*. *Tales of the TARDIS* is the opposite: a real show with its
own provider identity, listed like anything else.

It is an attribute rather than something inferred from the absence of external
references, because those are not the same fact: a show no provider has heard of
is still a show, and deriving this would make it disappear from listings for a
reason nobody chose. The default is `true`. It is called `listed` rather than
anything involving the word *companion*, which in this of all libraries already
means a person.

### Descriptive metadata only where Emby has none

The serial above carries `<title>` and `<outline>` because Emby has no item for
a serial. A `season.smd` carries neither: `season.nfo` is right there, Emby
reads it, the metadata manager edits it, and a second copy in the `.smd` would
be a divergence waiting to happen.

The rule is expressed by an attribute rather than left to the reader:
`<container type="season" id="season-14" nfo="season.nfo">` says *this
container's descriptive fields come from that file*. Three cases, and they are
exhaustive:

| The container | Descriptive fields come from | Types |
| --- | --- | --- |
| has `nfo` | that file | `series`, `season` |
| has presentations | its presentations' sidecars | `episode`, `movie` |
| has neither | the `.smd` itself | `serial`, `arc`, `volume`, `collection` |

Carrying fields in the first two cases is rejected by validation rather than
silently preferred, and omitting them in the third leaves the container nameless,
which is also an error. `nfo` must further be the sidecar Emby expects for the
type — a `series` container pointing at a `season.nfo` is a typo the validator
should catch, not a configuration.

The pointer is worth more than the convention it replaces: the editing UI needs
to know which file to open, and a later migration needs to know which facts came
from where.

### What `<outline>` is for

`<outline>` answers one question: why would a viewer choose this? The hook of a
story, what an extra has in it, what a cut offers that the default does not. One
sentence, in the contributor's own words, shown under the title wherever a
client lists the thing. It is not identification. "Season 14, story 6, six
parts, 1977" is already in the tree and the provider record, and a tool that
wants that line constructs it rather than reading a second copy that goes stale
the first time a story is renumbered.

The rule above says where it may appear. A container carries one only where
nothing else answers the question, which is why the serial at the top of this
document has one and the season does not: `season.nfo` holds the provider's
answer. An alternative always may, because no provider models a cut, and the
difference between the omnibus and the broadcast version is exactly what the
viewer choosing between them wants told. An item carries one on the same terms
as its title, only when no provider has one for it.

### No `<thumb>`, no `<bif>`, no per-entry asset list

The sketch listed `thumb` and `bif` on every entry, alongside the `nfo`. Two of
the three go: Emby's own convention is `{stem}-thumb.jpg` beside the video and
`{stem}.ext` inside `metadata/`, and trick-play indexes are `{stem}-320-10.bif`.
Anything that scans the library resolves those from the stem already, because it
has to: Emby spells one role several ways on disk, so a reader that works at all
works by rule rather than by list. Restating the files in the `.smd` gains nothing
and costs a rename.

The `nfo` stays, and the difference is not that it is harder to derive — it
follows from the same stem. It stays because the tool *writes* it, and a write
target should be declared rather than inferred: it is what an apply pass touches,
what a dry run lists, and what the validator compares across a version group. The
line is between files the tool reads and files it changes, and it will hold if
thumbs ever become something the tool generates.

The same rule extends to containers themselves, which is what makes it uniform:
**a container's stem is its own `.smd` filename minus the extension**, so
`… The Talons of Weng-Chiang.smd` gets its artwork from
`… The Talons of Weng-Chiang-thumb.jpg` by exactly the rule an episode uses. One
naming rule covers both, and a serial gets a poster without a new mechanism.

### `<sequence>`, not `<displayOrder>`

`<displayorder>` is already a tag in `tvshow.nfo`, holding `aired`, `dvd` or
`absolute`. A second `displayOrder` meaning something structurally different
would collide in conversation before it collided in code.

`<sequence>` holds `<item>` in the order they are meant to be watched. A
container usually has one; a container whose alternatives differ in shape has
one per shape, each carrying an `id` that an `<alternative>` names — see
"Alternatives name their sequence" below. There are no ordinal numbers in the
file. Numbers get derived at projection time, and the
absence of hand-written numbers is what makes inserting a newly-found prequel a
one-line edit rather than a renumbering pass.

**`exploded` says whether the children are worth showing as children.** A
sequence of child containers can be rendered two ways — as groups you descend
into, or inlined into one continuous run at this level — and which is right is a
property of the show, not of the client:

| Value | Meaning |
| --- | --- |
| `never` (default) | The children are real structure. Show them as groups. |
| `allowed` | Offer a continuous view; group by default. |
| `preferred` | Show the continuous view by default; keep grouping available. |

There is no value meaning "never show these children at all", and the omission is
deliberate. A level nobody should ever see is not a level — it should not be a
container, and if the fact is worth keeping it belongs in a field. The case that
looks like it needs one, a series with no seasons, needs nothing: its sequence
holds episodes, and the `Season 01/` folder those episodes live in never becomes
a container in the first place.

`exploded` is a display hint and nothing else. It does not reach the projection:
Emby renders one flat run per season whatever this says, and a client that
ignores the attribute entirely still shows a correct, if more clicky, library.

### `optional`, not `<critical>`

The sketch's `<critical>false</critical>` marks the prequel as skippable, which
is a genuinely useful thing to record and worth keeping. As an element it costs
a line on every essential item to say the unremarkable thing; as
`optional="true"` on the exception, the default is silence. Semantics: an
`optional` item is played when the container is played straight through, and is
skipped by a "story only" pass. It is not hidden, and it is not an extra —
extras are not part of the sequence at all.

### `<features>` and `<track>`, not `<inBand>` with fixed indices

This is the one structural correction rather than a naming one. The sketch put
`<audioTrackId>3</audioTrackId>` on the feature declaration, then let several
presentations claim to support it. But a mobile re-encode does not have the same
track layout as the full-bandwidth file — dropping a surround track shifts every
index after it — so a single index cannot be correct for both. The declaration
and the mapping are different facts:

- `<feature>` declares the *logical* thing — a commentary, an isolated score, a
  descriptive audio track — with an id, a type and a description. It is a
  property of the container.
- `<track>` inside a `<presentation>` maps that feature to *this file's* stream
  indices. A presentation that lacks a feature simply omits the mapping, which
  also replaces the sketch's `supports="commentary1, isolatedMusic1"` attribute
  and its space-vs-comma ambiguity.

Absent `subtitle` means no subtitle stream is part of the feature; `-1` as a
sentinel is not needed and is not accepted.

**A feature names its participants.** A commentary is mostly interesting for
who is on it, and "who" is a list, not a title string: `<participant name
role>` under `<feature>`, one per person, in the order they are credited. The
role is what the person is *to the programme* — a character name for an actor,
a job for crew — which is the same convention the NFO's `<actor>` uses, so a
client can render the two alike. The `.smd` carries names and roles only, as an
NFO does; provider ids for the people live in the shared database, which is
where a question like "every commentary this director recorded" gets asked.
The same element is accepted on an extras `<item>` for an interview or a
featurette, for the same reason.

**What makes two commentaries two features** is neither the recording session nor
the participant list: it is whether you would listen through them as one thing.
Tom Baker's solo commentary over parts 1 and 3 of *Pyramids of Mars* is one
feature, because that is one listening experience with a gap in the middle. A
commentary whose participants rotate between parts of a story — which the
Collection sets do routinely — is likewise one. Identity is the run.

**So participants can change within a single feature**, and that decides where
they hang. The list on the `<feature>` is the default, the people on it
throughout; a `<track>` may carry its own list, which replaces the default for
that item. Declare once, override where they swap. A participant list bound to
the feature alone could not describe a commentary whose line-up changes at part
three, which is a thing that exists.

**And the run itself is derived, never declared.** A feature's sequence is the
items whose selected presentation maps it, in the order of the sequence those
items belong to — for Tom Baker's, `[part 1, part 3]`, skipping the parts he is
not on. A client builds the playlist from the mappings that already exist.
Declaring it as well would state one fact twice, and two statements of one fact
can disagree; a derived one cannot.

That also settles the case which would otherwise need special handling: a
commentary recorded over the omnibus rather than over the parts. The mapping
lives on the presentation and presentations belong to sequences, so the derived
run follows whichever sequence the commentary was actually recorded against,
with no extra machinery and nothing to keep in step.

Stream indices are still brittle — a remux renumbers them. The verification pass
described below re-probes each presentation and reports a mapping that no longer
resolves, on the principle this format applies throughout: a file Emby will not
read, or a reference that no longer lands, is shown and labelled rather than
silently dropped. Absence and breakage are the things a curation tool exists to
surface.

### `<alternatives>` with an explicit default

Every alternative has an id; the default is named once on the parent rather than
flagged on a child, so "exactly one default" is structural instead of a
validation rule. `id="use"` in the sketch was doing the work of a default flag
under a name that says nothing about the content; ids should read as what they
are (`broadcast`, `se`, `extended`, `subbed`).

A `<presentation>` with no `alternative` attribute serves **all** the
alternatives that name its sequence. That is the fallback that makes the format
usable: an updated-effects release usually re-does two episodes out of six, and
without the fallback the other four would each need a duplicate presentation
entry pointing at the same file. When an alternative is selected, each item
takes the presentation matching it, or the unqualified one if there is none.

### Alternatives name their sequence

Two alternatives can differ in one of two ways. The updated-effects release is
the same six parts with different files for some of them: same **shape**,
different presentations. An omnibus edition is one film cut from the six parts:
a different shape altogether. The first draft of this format handled only the
first, which left the omnibus — common enough in classic-TV releases that
*The Daleks in Colour* is a 75-minute recut of a seven-part serial sold on its
own disc — with nowhere to go.

The fix is to make the sequence a named thing that alternatives point at, rather
than a property of the container:

```xml
<alternatives default="broadcast">
  <alternative id="broadcast" sequence="parts"><title>Broadcast version</title></alternative>
  <alternative id="se"        sequence="parts"><title>Updated special effects</title></alternative>
  <alternative id="omnibus"   sequence="omnibus"><title>Omnibus edition</title></alternative>
</alternatives>

<sequence id="parts"> … six items … </sequence>
<sequence id="omnibus"> … one item … </sequence>
```

An earlier draft nested the omnibus sequence inside its `<alternative>`, which
left a branch in every rule — "has its own sequence or not" — and could not
express two alternatives sharing the omnibus shape, a colourised and a
monochrome omnibus, say. Naming removes the branch: every alternative names
exactly one sequence, and sharing is two alternatives naming the same one. The
rules, each of which the validator checks:

- **Every alternative names exactly one sequence, and every sequence with an id
  is named by at least one alternative.** An orphan sequence is an error, not a
  hidden view.
- **A container with no `<alternatives>` has exactly one `<sequence>`, and it
  needs no id.** The common case — a season, a series without cuts — is as short
  as it was.
- **A qualified presentation must name an alternative on its own sequence.**
  `alternative="se"` is legal on an item in `parts` and an error on one in
  `omnibus`, because `se` does not name `omnibus`.
- **An unqualified presentation serves every alternative that names its
  sequence.** This is the fallback above, stated once for all shapes rather than
  only for the main one. The omnibus item's single presentation serves every
  omnibus-shaped alternative by the same rule that a broadcast part's serves
  `broadcast` and `se`.
- **Ids are unique across the container, not per sequence.** `parts` and
  `omnibus` may not both contain a `part1`. Container-wide uniqueness is what
  lets a `ref` (below) and an extras `anchor` name an item without saying which
  sequence it is in, and keeps the journal key a single token.
- **The `default` attribute names an alternative, and that alternative's
  sequence is the one the projection walks.** What the other sequences become in
  Emby is set out under "Projection".

An `episode` or `movie` container holds presentations rather than a sequence, so
alternatives declared there omit `sequence`: the presentation set is the one
sequence, and qualification works as it always did. Alternatives inherited from
an ancestor apply to a child container's own sequence when it has one and to its
presentations when it does not — the same resolution as for features, and it is
why part 1's file can say `alternative="se"` without declaring anything.

**An item may stand in for an item in another sequence.** A sequence that
reorders the same episodes — DVD order beside broadcast order, or the decades-old
argument about *The Prisoner* — would otherwise have to restate every item and
every presentation. Instead it holds references:

```xml
<sequence id="dvd-order">
  <item ref="part2"/>
  <item ref="part1"/>
</sequence>
```

A `ref` item has no `id`, no presentations and no children; it resolves to the
item it names, which is in another sequence of the same container or, in the
form `ref="container-id#item-id"`, in another series entirely (see "Secondary
series" below). It is
not a second home, so principle 5 holds: the item is declared once, its resume
point and watched state are keyed to that one id, and a ref is a position in an
order rather than a copy of a thing. That gives every alternative a complete
sequence of its own, so a client playing one straight through never merges two
lists. A hybrid — four parts as broadcast and
the last two recut into one — is four refs followed by a new item. The shapes
this covers, each with the one construct:

| Release | Sequence holds |
| --- | --- |
| Omnibus | one new item |
| Reorder | refs only |
| Two 45-minute parts beside four 25-minute parts | new items only |
| Broadcast parts 1–4, then a recut of 5–6 | refs, then one new item |

### Secondary series

Two things a library holds that the tree above cannot place on its own:

- **A companion series.** *Doctor Who Confidential* is a series in its own
  right — its own TVDB id, its own Emby series, seven seasons that pair one to
  one with *Doctor Who* series 1–7 — whose every episode is about one episode
  of the other programme. From *Doctor Who*'s side it is an extra; from its
  own it is an episode.
- **Extras that form a series.** *Behind the Sofa* on *The Collection* box sets
  is one featurette per story, filed in each story's extras, and also worth
  watching as a run. No provider knows it exists.

Both are the same mechanism, a reference across containers, and they resolve the
same way. **A run of related items that reads as a programme is a container, and
its items live in it.** Confidential episodes live in
`Doctor Who Confidential (2005)/tvshow.smd`; *Behind the Sofa* instalments live
in `Behind the Sofa/tvshow.smd`, with a season container per box set. A story
points at one from its extras, whichever it is:

```xml
<extras>
  <item ref="doctor-who-confidential#s1e1"/>
  <item ref="behind-the-sofa#s13-pyramids"/>
</extras>
```

What differs between the two is not where they live but whether anyone should be
able to browse to them:

```xml
<container format="1" type="series" id="behind-the-sofa" listed="false">
  <title>Behind the Sofa</title>
  <sequence>
    <item type="container" id="behind-the-sofa-13" smd="Season 13/season.smd"/>
  </sequence>
</container>
```

An earlier draft had *Behind the Sofa* living in each story's extras with a
container of refs pointing back *at* them — the inverse of this. Giving both
companion series the same shape is worth the change: one rule covers them, and
the difference between them reduces to two flags, whether a provider knows them
and whether they are `listed`. The rule about where a file is filed still governs
a loose featurette that belongs to one story and nothing else; what changed is
that a run which reads as a programme is no longer treated as loose extras that
happen to be related.

Where the item's *file* sits on disk follows its home, which is worth saying
plainly because it is briefly surprising: a *Tales of the TARDIS* episode ripped
from a *Doctor Who* box lands in the *Tales of the TARDIS* series folder, and the
binding is what records which disc it came off.

The cross-container form of `ref` is `container-id#item-id`, where the first
half is the `id` of a series' root container. It is an id, not a path, so it
does not breach the rule that paths stay inside the series: the client resolves
it through its index of `tvshow.smd` files, and a series that is absent simply
leaves the ref unresolved, reported the way a missing file is. Series root ids
are therefore unique across a library, which the validator checks, and it is
one more reason for them to read as what they are.

Everything said about refs holds unchanged. The target keeps its one home, its
resume point and its watched state; a ref in an extras list is shown among the
extras and a ref in a sequence is shown in the run, and neither creates a copy.
Principle 5 survives because the tree of *homes* is still a tree; refs are a
second index over it, not a second place for anything to live.

The **matched seasons** are a fact about containers rather than items, and are
declared once on the companion:

```xml
<container format="1" type="season" id="confidential-1" nfo="season.nfo">
  <related container="doctor-who#season-1" role="companion"/>
  …
</container>
```

A client that finds a `companion` relation between two seasons may pair their
items by position — Confidential episode *n* with series episode *n* — where no
explicit ref exists. That is a derivation, and an authored ref always wins over
it, because the pairing is not always one to one: Confidential's specials and
the cut-down "Confidential Cut Down" repeats are exactly the sort of thing that
breaks the count.

**Projection.** Emby has no cross-series link, so a cross-container ref projects
to nothing: Confidential stays a series of its own, and a person using Emby finds
it there. A library that wants the extras row anyway can hardlink the file into
the episode's extras folder — same bytes, one inode, and an extra NFO the writer
already knows how to emit — but that is an opt-in the tool should offer rather
than a default, and it is listed under open questions.

Moving *Behind the Sofa* to its own container sharpens that. Under the earlier
arrangement its instalments were filed in each story's extras, so Emby showed
them where they belonged and only a container-aware client could watch them as a
run; now it is the other way about, and Emby sees a separate programme with no
extras rows at all. Six files in the first box alone, which promotes hardlinking
from a theoretical convenience to the thing that decides whether the Emby view of
a Collection box still reads correctly.

`profile` replaces the sketch's `bandwidth`, and it is an open vocabulary
(`mobile`, `hdr`, `sdr`, `remux`). The sketch's first presentation had no
`bandwidth` while its siblings had `full`, which reads as a missing value rather
than a deliberate one. Unqualified means "the presentation to use unless the
client asks for something specific", and stating `profile="full"` is redundant.

**The filename is a user-visible string, so the tool owns it.** Because every
presentation of an item is an Emby version of one episode, and because Emby
labels those versions from the filename, the on-disk name is no longer an
internal detail — it is what an Emby user picks from. That gives the writer a
job it would not otherwise have: each presentation's file must be named
`{episode stem} - {display name}.ext`, where the display name is the
`<alternative>`'s title for an alternative and the profile's name for a profile.
Validation compares the two and reports a drift rather than silently resolving
it, because the disagreement is between what the file says to a person and what
the `.smd` says to a client.

Two consequences follow from the selector showing the whole filename rather than
the documented trailing segment. Alternate filenames should be **identical up to
the final segment**, so the only difference sits at the end of a long string
where it can be read; and the `.smd` should not be written as though the
selector will improve, because designing around an unshipped fix is how a format
acquires a dead field.

### NFOs hang off presentations, because that is where they live

An earlier draft put `nfo` on the `<item>` and made the tool maintain a single
sidecar on whichever version sorted first. That was wrong in two ways. An item is
an abstraction NFOs do not have — Emby has no file for "the episode", only files
for the episode's versions — and the design left every other sidecar in the group
untracked, shadowed, and one rename away from being silently promoted over the
one the tool maintains.

So the NFO belongs to the presentation:

```xml
<item type="episode" id="part1">
  <presentation nfo="… Part 1 - Broadcast version.nfo"
                file="… Part 1 - Broadcast version.mkv"/>
  <presentation profile="mobile"
                nfo="… Part 1 - Mobile.nfo"
                file="… Part 1 - Mobile.mkv"/>
</item>
```

**Nothing is shadowed because nothing is untracked.** Every sidecar in a version
group is named in the `.smd`, so the writer maintains all of them and the
validator checks all of them. Which one Emby reads stops being a question the
design has to answer correctly — it only has to make the answers agree.

Three things follow.

**Agreement is the invariant, not identity.** The fields that describe the
episode — title, plot, identity numbering, and the display numbering the
projection writes — must be the same in every NFO of a group, and validation
reports a divergence. The fields that describe *a file* — runtime, and anything
derived from the streams — may differ, because an extended cut genuinely is
longer than the broadcast one. A rule of "make them identical" would be simpler
to implement and would be lying about the extended cut.

**The rename rule disappears.** Adding an `Abridged` version that sorts ahead of
`Broadcast version` no longer moves anything: the new presentation brings its own
NFO, written with the same shared fields as its siblings, and Emby reads whichever
it reads. The failure mode that argued hardest for the tool owning filenames —
silent, invisible, metadata simply stops being read — is designed out rather than
guarded against.

**An item joins the model by its files, not by a sidecar.** With `nfo` gone from
`<item>`, the join to an `Episode` is the version group its presentations form,
which is also how Emby sees it. The item's identity is its `id` and its files;
nothing about it is stored in a file Emby owns, which is correct, because Emby
has no concept of it.

The cost is that a single-version episode now writes two lines where it wrote
one, and that `<extras>` items take a `<presentation>` too rather than naming a
file directly. Uniformity is worth it: one rule — *files and NFOs hang off
presentations, presentations hang off items* — beats a shorthand that has to be
unlearned the first time an extra acquires a mobile encode.

### `<source>` and `<chapter>`: what the tool knows at rip time and nowhere else

Two more children of `<presentation>`, both optional, both recording facts that
are known when a file is made and unrecoverable afterwards.

```xml
<presentation nfo="…" file="…">
  <source disc="3F1A…C2E9" playlist="00004.mpls"/>
  <chapter index="1" title="Opening titles"/>
  <chapter index="2" title="Fog on the Thames"/>
</presentation>
```

**`<source>` says which disc and which playlist the file was ripped from.** The
`disc` is the content hash the shared database and TheDiscDb both key on, and
`playlist` is the playlist name — the pair that identifies a disc title by its
natural key, rather than an opaque id minted somewhere else. That keeps a
hand-edited file self-describing. What it buys is the round trip: a correction
made in the library can be sent back to the store against the right pressing,
and a second copy of the same disc binds to the same items without anyone
typing. It is the one attribute in the format that names something outside the
library, and it is optional for that reason — a file whose provenance nobody
recorded is simply a file.

**`<chapter>` names the chapters.** Blu-ray chapters are usually unnamed on the
disc and the names, where anyone has them, are authored knowledge. Principle 4
would seem to exclude them — an MKV carries chapters natively, so they are
discoverable — but the tool *writes* them, into the container file at rip time
so that any player shows them, and a write target is declared. The verification
pass compares the two, exactly as it does for track indices, and a file whose
chapters no longer match its `.smd` is reported rather than silently trusted
either way.

### `<extras>`, not `<outOfBand>`

The vocabulary already exists, so the `type` attribute on an extras `<item>`
borrows it: Emby's own `ExtraType` enum — `featurette`, `behindTheScenes`,
`deletedScene`, `interview`, `trailer`, `scene`, `short`, `clip`, `themeSong`,
`themeVideo` — with the nine folder names that imply them. A client that already
groups an item's extras by type groups a container's the same way, with no
translation table in between. The in-band/out-of-band pairing was accurate but it
is jargon in a file people hand-edit; `<features>` and `<extras>` say what each
is.

An extra listed here is *owned by the container*. That is the level Emby cannot
express, and it is the whole reason the element exists — an extra about a serial
is otherwise forced to choose between a season folder and one arbitrary part.

Which choice it makes now matters, because the three placements do not render
alike. Filed under the series it lands in **Specials**, where it sits among real
season-0 episodes and is indistinguishable from them. Filed under the season it
is **appended to the end of the season**, so a featurette about a serial 20
episodes back turns up after the finale. Filed inside an episode folder it gets
a genuine **Extras row**. Only the third is what an extra actually is, so:

**Container extras are filed in the episode folder of the container's anchor.**
`<extras anchor="part1">` names a sequence item by id, the extras are filed under
that item's episode folder, and the `.smd` records that they belong to the
serial rather than to that part. Emby shows them on part 1's page — the best
approximation it can render — and a container-aware client shows them on the
serial.

Absent an `anchor`, the extra is filed at the container's own level and the
`.smd` simply records where it went. That is the right default at the top: a
series-level documentary anchored to some arbitrary episode is worse than one
Emby files under Specials, because at least Specials is where a person would
think to look for it. Anchoring is for containers whose extras are *about a
story* — a serial, an arc — where an episode page is a better home than the tail
of a season.

The cost is one asymmetry on disk: the anchor item needs its own `S14E21/`
folder while its siblings sit loose in the season folder. That is worth paying,
because the alternatives are a featurette masquerading as a special or as the
27th episode of a 26-episode season.

Two mechanical details follow from the same measurement. An extra's NFO **is**
read, so an extra is not the metadata-free thing it is usually taken for — which
is why an extras `<item>` carries a `<presentation>` with an `nfo` attribute like
any other item, rather than naming a bare file. And an NFO for an episode-level
extra must be rooted at `<movie>`, so a writer branches on placement, not on what
the file obviously is.

### Everything is relative and stays inside the series

Paths in `file`, `nfo` and `smd` are relative to the folder holding the `.smd`
that names them.
A path may traverse into a sibling folder (`../Season 15/…`, for a story that
straddles a season boundary) but may not escape the series folder. Series are
the unit that gets moved, backed up and re-pointed, and a reference out of one
would break the first time that happened.

## Where the files live

A `.smd` exists for a **container**, never for a folder. A season folder gets a
`season.smd` when there is a season container, and a series with no seasons has a
`Season 01/` folder with no `.smd` in it at all — the episodes inside it are
named by the series container, across the folder boundary, like any other
relative path.

Where a container does correspond to a folder, the convention mirrors the NFO
convention exactly, so there is nothing new to remember:

| Container | File | Beside |
| --- | --- | --- |
| Series | `tvshow.smd` | `tvshow.nfo` |
| Season | `season.smd` | `season.nfo` |
| Episode | `{item stem}.smd` | its presentations' sidecars |
| Movie | `{item stem}.smd` | its presentations' sidecars |
| Serial / arc / volume | `{name}.smd` | nothing — it has no Emby item |

An episode's `.smd` is named for the **item**, not for a version —
`Doctor Who S01E01.smd` sits beside
`Doctor Who S01E01 - Broadcast version.mkv` and its siblings, and there is no
`Doctor Who S01E01.mkv` at all. That reads as a dangling name until you notice it
is the point: the item is the abstraction Emby has no file for, and the `.smd` is
that file. It is also what gives the item an artwork stem of its own, by the same
rule a serial gets one.

A container with no Emby counterpart is named freely and lives in its parent's
folder; the sketch's
`Doctor Who (1963) - 4s - The Talons of Weng-Chiang.smd` sits in
`Season 14/` and satisfies this as written.

**Discovery starts at `tvshow.smd` and follows references.** A child container
is either an `<item type="container" smd="…"/>` pointing at another `.smd`, or
an inline `<container>` element nested directly in the sequence. Give a
container its own file when it owns a folder or is large enough to edit alone;
inline it when it is a grouping of a handful of items that would otherwise
scatter a season across eight files.

Every pointer attribute is named for what it points at — `nfo`, `file`, `smd` —
so a line can be read without knowing the schema, and a grep for `smd=` finds
every cross-file edge in a library.

An `.smd` on disk that nothing references is a warning, not content. Reachability
being the test means an abandoned draft cannot quietly change what a client
renders.

## Worked examples

Classic *Doctor Who* exercises every level at once: seasons that are real, a
serial layer Emby has no room for, and an episode carrying three versions and two
commentaries. Three files, linked by `smd` attributes, relative to each other. A
fourth example then does the opposite, and models fewer levels than the folders
have.

### `Doctor Who (1963)/tvshow.smd`

```xml
<container format="1" type="series" id="doctor-who" nfo="tvshow.nfo">

  <!-- The seasons are real, but this library is watched as one continuous run
       of stories, so a client should default to the flat view and keep the
       season grouping a click away. -->
  <sequence exploded="preferred">
    <item type="container" id="season-1" smd="Season 01/season.smd"/>
    <!-- Seasons 2 to 13. -->
    <item type="container" id="season-14" smd="Season 14/season.smd"/>
    <item type="container" id="specials" smd="Specials/season.smd"/>
  </sequence>

  <!-- No anchor: these are about the programme, not about a story, so they are
       filed under the series and Emby shows them in Specials. -->
  <extras>
    <item type="featurette" id="whose-doctor-who">
      <presentation nfo="featurettes/Whose Doctor Who.nfo"
                    file="featurettes/Whose Doctor Who.mkv"/>
    </item>
  </extras>
</container>
```

### `Doctor Who (1963)/Season 14/season.smd`

```xml
<container format="1" type="season" id="season-14" nfo="season.nfo">

  <!-- Six stories, 26 episodes. Both readings are legitimate, so offer the
       continuous one without making it the default. -->
  <sequence exploded="allowed">
    <item type="container" id="the-masque-of-mandragora"
          smd="Doctor Who (1963) - 4s - The Masque of Mandragora.smd"/>
    <!-- Four more stories. -->
    <item type="container" id="talons-of-weng-chiang"
          smd="Doctor Who (1963) - 4s - The Talons of Weng-Chiang.smd"/>
  </sequence>
</container>
```

Nothing here says `Season 14/`: paths are relative to the file naming them, and
this file is already in that folder. The season carries no `<title>` or
`<outline>` because `nfo="season.nfo"` says where those live.

### `… /Season 14/S14E21/Doctor Who (1963) - s14e021 - … Part 1.smd`

The serial's own `.smd` is the one at the top of this document. Its first item
was written inline there; here it is instead pulled out into its own file,
because three versions, two feature mappings and an extras row are enough to want
their own document. The two forms are equivalent — inline and referenced are the
same container seen from the parent or from itself.

```xml
<container format="1" type="episode" id="part1">

  <!-- No nfo attribute and no descriptive fields: this container's metadata
       comes from its presentations' sidecars, which the writer keeps in
       agreement. commentary1, music1 and the "se" alternative are not declared
       here either. They resolve upwards, to the serial that owns them. -->

  <presentation nfo="Doctor Who (1963) - s14e021 - … Part 1 - Broadcast version.nfo"
                file="Doctor Who (1963) - s14e021 - … Part 1 - Broadcast version.mkv">
    <track feature="commentary1" audio="3"/>
    <track feature="music1" audio="4"/>
  </presentation>

  <presentation profile="mobile"
                nfo="Doctor Who (1963) - s14e021 - … Part 1 - Mobile.nfo"
                file="Doctor Who (1963) - s14e021 - … Part 1 - Mobile.mkv">
    <track feature="commentary1" audio="2"/>
  </presentation>

  <presentation alternative="se"
                nfo="Doctor Who (1963) - s14e021 - … Part 1 - Updated special effects.nfo"
                file="Doctor Who (1963) - s14e021 - … Part 1 - Updated special effects.mkv"/>
</container>
```

An `episode` container holds `<presentation>` directly instead of a
`<sequence>`, because it has versions rather than children. That is the same
shape an `<item>` has, which is the point: `<item>` and `<container>` are one
structure seen from two sides, and moving a subtree into its own file is a cut
and a paste rather than a translation.

### Ids resolve up the tree

Part 1 references `commentary1` and the `se` alternative without declaring
either, and it does so across a file boundary. **An item may reference any
feature or alternative declared by itself or by an ancestor**, which is what
makes a commentary spanning all six parts declarable once, on the serial that
owns it, rather than repeated in six files that then have to be kept in step.

Redeclaring an ancestor's id lower down is an error rather than a shadowing rule.
Shadowing would make the meaning of `commentary1` depend on where the reader
happened to start, and no reading of a library that spans several files should
turn on that.

The `id` on a referencing `<item>` repeats the `id` in the referenced container.
That is deliberate denormalisation: `anchor="part1"` has to resolve without
opening every child file, and a parent should be readable on its own. Validation
checks the two agree, which is the trade this format keeps making — duplicate
for legibility, verify mechanically.

### A series with no seasons

*The Prisoner* is 17 episodes, one run, and a decades-old argument about what
order they go in. There is no season in it — only a `Season 01/` folder, because
Emby wants one and the metadata providers match against it.

`The Prisoner (1967)/tvshow.smd`:

```xml
<container format="1" type="series" id="the-prisoner" nfo="tvshow.nfo">

  <!-- No season container anywhere. The episodes sit in Season 01/ on disk and
       are named across that boundary like any other relative path. -->
  <sequence>
    <item type="episode" id="arrival">
      <presentation nfo="Season 01/The Prisoner - s01e01 - Arrival.nfo"
                    file="Season 01/The Prisoner - s01e01 - Arrival.mkv"/>
    </item>

    <!-- An episode with an alternative cut earns its own file; the rest do
         not. -->
    <item type="container" id="chimes-of-big-ben"
          smd="Season 01/The Prisoner - s01e02 - The Chimes of Big Ben.smd"/>

    <!-- The remaining fifteen, in the order this library argues for. -->
  </sequence>
</container>
```

This is the whole mechanism. There is no flag saying "seasonless", no season
container marked as scenery, and nothing for a client to special-case: a series
with no seasons is a series whose sequence holds episodes. The `Season 01/`
folder still holds `season.nfo`, Emby still shows a season, and the two facts
never have to be reconciled because they were never claimed to be the same fact.

The same freedom runs the other way. A show whose seasons are real and whose
serials are real gets both levels, as *Doctor Who* does above; a show released in
volumes that cut across its broadcast seasons gets volumes, while the folders
keep the seasons the providers need. **Levels are modelled where they exist**,
and the folder layout is a separate question with a separate, Emby-shaped
answer.

## What Emby is left holding

Three mechanisms now, two of them Emby's own.

**Unknown extensions are ignored.** Emby indexes by extension; `.smd` is in none
of its lists, so the files are inert. Anything that reports unplaced files has to
learn the same, or every container file becomes a spurious warning in the one
report that exists to find real ones.

**Alternative presentations use Emby's multi-version naming.** This was the sharp
edge, and the sketch ran straight into it: naming the updated-effects files
`s14e121`, `s14e122` gives them valid `SxxExx` patterns, so Emby indexes six
extra episodes in a nonexistent hundred-block. The earlier draft of this proposal
answered that by hiding them behind an `.ignore` file. Now that episodes are
known to support versions, hiding is the wrong answer: name every presentation
`{episode stem} - {display name}.ext`, leave them all in the same folder, and
Emby groups them under one episode with a version picker. No phantom episodes, no
hidden folders, and Emby users get the alternatives too — labelled by filename,
which is why the writer owns the filename.

`.ignore` survives only as an escape hatch for a presentation that should exist
without appearing in the picker — a low-bitrate re-encode kept for one device,
say. It is not used by default, and whether it works at all in the installed
version is still unverified; nothing in the design depends on it.

**Container extras are anchored to an episode folder,** for the reasons set out
above: it is the one placement Emby renders as extras rather than as episodes.

The on-disk result for the worked example:

```
Doctor Who (1963)/
  tvshow.nfo
  tvshow.smd
  Season 14/
    season.nfo
    Doctor Who (1963) - 4s - The Talons of Weng-Chiang.smd
    Doctor Who (1963) - 4s - The Talons of Weng-Chiang-thumb.jpg
    Doctor Who (1963) - s14e042 - … Prequel.mp4
    Doctor Who (1963) - s14e042 - … Prequel.nfo
    S14E21/
      Doctor Who (1963) - s14e021 - … Part 1 - Broadcast version.mkv
      Doctor Who (1963) - s14e021 - … Part 1 - Broadcast version.nfo
      Doctor Who (1963) - s14e021 - … Part 1 - Broadcast version-thumb.jpg
      Doctor Who (1963) - s14e021 - … Part 1 - Mobile.mkv
      Doctor Who (1963) - s14e021 - … Part 1 - Mobile.nfo
      Doctor Who (1963) - s14e021 - … Part 1 - Updated special effects.mkv
      Doctor Who (1963) - s14e021 - … Part 1 - Updated special effects.nfo
      Doctor Who (1963) - s14e021 - … Part 1 - Omnibus edition.mkv
      Doctor Who (1963) - s14e021 - … Part 1 - Omnibus edition.nfo
      featurettes/
        Doctor Who (1963) - The Talons of Weng-Chiang - Now and Then.mkv
        Doctor Who (1963) - The Talons of Weng-Chiang - Now and Then.nfo
        Doctor Who (1963) - The Talons of Weng-Chiang - Now and Then-thumb.jpg
    Doctor Who (1963) - s14e022 - … Part 2.mkv
    …
```

Emby sees season 14 with its 26 episodes, part 1 offering four versions and
carrying a featurette in its extras row, and nothing duplicated or missing. What
it does not see is that six of those episodes are one story, that the featurette
is about the story rather than about part 1, that two of the four versions are
the same cut at different bitrates, that the fourth is not a version of part 1
at all but the whole story as one film, or that there is a commentary on audio
track 3. All five of those are sitting in the `.smd` beside it.

## Projection: what Emby is told about order

The container tree is the source of truth. Emby gets an approximation of it,
written into the NFOs it already reads, by a flattening pass:

1. Walk the tree depth-first in document order, skipping `<extras>`.
2. Assign each reached item consecutive display positions starting at 1.
3. Write `<displayseason>`/`<displayepisode>` into **every** NFO of that item's
   version group, preserving every element the tool does not manage.

Step 3 writing to the group rather than to one file is what makes the projection
independent of Emby's choice of first NFO. It is also why display numbering is on
the list of fields that must agree across a group: a projection that landed in
one sidecar and not its siblings would produce an order that depends on which
file the scanner happened to reach first.

Three of Emby's rules bind the pass, and all three are load-bearing:

- **Ordering values must be greater than zero,** so nothing can be placed ahead
  of episode 1 without renumbering the whole display season. The projection
  therefore always numbers a whole display season at once rather than patching
  individual items.
- **Identity numbering is never touched.** `<season>`/`<episode>` keep matching
  the provider; only display numbering moves. A prequel that airs between two
  serials keeps whatever identity number it really has.
- **Five tags, two properties.** The writer must clear a competing
  `<airsbefore_season>` or `<airsafter_season>` rather than append past it,
  since document order decides the winner and an unnoticed earlier tag makes the
  result depend on where in the file the new one landed.
- **Season 0 is not only specials.** A series-level extra is merged into the
  Specials season, so anything filed there is competing for display positions
  with the real season-0 episodes the projection is numbering. Extras anchored to
  an episode folder stay out of that competition entirely, which is a second
  reason to prefer the anchor over series-level filing.

What survives the projection is the **order**. What is lost is the **grouping**:
Emby lists 26 episodes of season 14 in the right sequence, with no indication
that six of them are one story. That loss is acceptable and is the whole reason
the `.smd` exists — a container-aware client reads the grouping, and Emby gets
a library that is at worst as good as it is today.

Only the default alternative's sequence is walked. The same-shaped alternatives
that name it are already in Emby as versions of its items, which is what the
filename rule above arranges. An item in a **non-default sequence** has no
counterpart to be a version of, and gets one of two treatments. If the provider
knows it — *The Daleks in Colour* is a TVDB special in its own right — it is
written as that item, with display numbering placing it after the run it is a
cut of. If the provider does not, the projection files it as a version of the
default sequence's **first** item, named `{stem} - {alternative title}.ext`, so
Emby offers it from that item's picker and no identity number is invented. That
is why the omnibus in the example at the top is named as a version of part 1.
A `ref` item projects to nothing: the item it points at is already there.

Seasonless series are the one case where projection has to invent something,
because the tree it is flattening has one level fewer than the thing it is
flattening onto. The recommendation is to leave identity numbering alone and
project the whole run into display season 1 — the season the episodes are already
filed under — rather than manufacture display seasons from the sequence. The
same reasoning rejects one display season per serial for classic *Doctor Who*: it
would put 155 near-empty seasons in Emby's UI and multiply the renumbering
surface by 155, to express a grouping the `.smd` already carries for the clients
that can read it.

## The migration this leaves open

Nothing above requires Emby to stay in the picture forever, and the layering is
what keeps that door open. Every fact lives at the level that owns it, and every
file the tool writes is pointed at from that level:

| Level | Points at | Holds what Emby cannot |
| --- | --- | --- |
| `<container nfo="…">` | `tvshow.nfo`, `season.nfo` | Type, ordering, alternatives, features |
| `<item>` | nothing — Emby has no file for it | The item's existence as one thing across its versions |
| `<presentation nfo="…">` | that version's sidecar | Which alternative and profile the file is, its track map, its chapters, and the disc it came from |

Consolidating to `.smd` alone is then a mechanical pass rather than an
archaeology project: read each pointed-at NFO, inline its fields into the element
that points at it, delete the file. Container fields land on the container,
per-file fields land on the presentation, and the item keeps what it already had
— which is exactly the fact that had nowhere to live in Emby's model in the first
place. Nothing has to be guessed at, because nothing was ever stored at a level
that could not name it.

The reverse direction works too, and matters more in the short term: the same
mapping regenerates a complete, ordinary Emby library from a `.smd` tree, which
is the rollback plan and the disaster-recovery plan in one.

## What this asks of an implementation

Roughly one new pass at each stage a library tool already has, which is the test
of whether the format fits a model built for Emby's shape rather than fighting it:

- **A model.** `Container`, `Sequence`, `SequenceItem`, `Presentation`,
  `Feature`, `Alternative`, `Relation` — structurally parallel to
  series/season/episode and, like them, keeping identity separate from
  presentation.
- **A parser.** Read `.smd`, resolve `smd` references from `tvshow.smd` outward,
  and report files nothing points at.
- **A resolver**, flattening the tree into the sequence a client renders and
  joining each item to the episode its presentations group into. This is the
  sibling of whatever already resolves Emby's own display order, not a
  replacement for it: one produces Emby's view, the other the container view, and
  comparing them is how the projection is checked.
- **A write path** that queues projection writes as reviewable changes, so
  container edits are applied deliberately rather than by rewriting NFOs behind
  the user's back.
- **A `<movie>`-rooted NFO** for an episode-level extra, which both the reader
  and the writer need, and which most existing code will not have, since the
  usual assumption is that an extra has no NFO at all and an episode's NFO is
  `<episodedetails>`.
- **Validation, as its own pass**, reported the way scan warnings are: ids unique
  within a container, every alternative naming a sequence that exists and every
  named sequence named by some alternative, qualified presentations naming an
  alternative on their own sequence, every `ref` resolving to an item in another
  sequence of the same container or to a `container-id#item-id` in another
  series, series root ids unique across the library, exactly one home container
  per item, every referenced path present, no descriptive metadata on a container
  that has an NFO, alternative references resolving, every `<track>` mapping
  resolving against the streams actually in the file, every `<chapter>` list
  matching the chapters the file carries, and every presentation filename
  matching the display name of the alternative or profile it claims — the last
  one being user-visible in Emby's version picker, so a drift there is a bug a
  person will see.

Two of the measurements above break assumptions that library tools tend to hold
already, rather than merely adding to them. Extras are widely modelled as
carrying no metadata, so they get no detail view and no sidecar handling; both
have to change, and an extra becomes an item that can be inspected like any
other. And asset scanning usually maps a file to what it provides on the
assumption that one stem is one item — a version group puts three stems on one
item, so grouping has to happen before that inventory is computed, or part 1
reports three of everything.

Grouping also gives a detail view something new to show, and it is deliberately
*not* the treatment a shadowed file gets. A sidecar on a non-first version is not
a file being ignored in favour of a better one; it is one member of a set that is
maintained together. So the view for a version group lists every NFO in it, marks
which one Emby reads, and flags the fields that disagree. Shadowing says "this
file is inert" — the right message here is "these files must say the same thing,
and one of them does not".

### Subsumption, and what the two views are for

An editor built for Emby browses the Emby view: three fixed columns, Series →
Seasons → Episodes, over resolved display order. Adding containers means a second,
container-shaped view and a toggle between them, and the obvious objection to a
container-only view is the seasonless series — no season row, so nowhere to edit
`season.nfo` from.

Seasonless is not the main case, and it is not even the common one. Four kinds of
Emby entity have no container of their own:

1. **The season of a seasonless series.** One row, one `season.nfo`, the case
   that prompts the question.
2. **Specials.** Probably the most common of the four. A container tree that
   interleaves specials into the sequence where they belong — which is the whole
   reason display numbering exists — has no reason to hold a "Specials"
   container at all. `Specials/season.nfo` and `season-specials-poster.jpg` are
   still there, still read, still editable.
3. **Seasons replaced by a different level.** Principle 2 permits volumes or arcs
   that cut across the broadcast seasons, and then the seasons on disk map to
   nothing in the tree. Here the abstracted-away season is not one row but
   several, so a special case built for the seasonless series would not stretch
   to cover it.
4. **Episodes no container references.** Every new file arrives this way. This is
   the one that matters most, because placing them is the daily work, and a view
   that cannot show an unplaced episode cannot be the view you work in.

So a special case for the seasonless series would fix a quarter of the problem.
The instinct behind it is right, though, and generalising it costs less than
special-casing it:

**Every Emby entity with no container of its own is subsumed by the nearest
container whose subtree holds its files, and is reachable from that container.**
A seasonless series offers Series Details and Season 1 Details together. A series
whose specials are interleaved offers Season 0 Details. A series whose seasons
have been replaced by volumes subsumes all of them. An unreferenced episode is
subsumed by whichever container's folder it sits under, which is where someone
would look for it anyway.

Two details make it work rather than merely tidy. The subsumed entity should
arrive **whole**, not as a bare NFO editor: a subsumed season owns its poster and
its `seasonXX-` artwork up in the series folder, and dropping those on the floor
would trade one unreachable file for four. And subsumption must be **counted and
reported** — "2 seasons subsumed, 3 episodes unplaced" belongs in whatever
summary the tool prints, because an entity that is quietly absorbed and never
mentioned is content that can hide.

One caveat for any editor that counts what an item supplies — "6 of 11 present",
and the like. Subsumed entities do not belong inside that count. Such a roster is
fixed per level, which is what makes the number comparable between items; a
variable roster turns a figure you can scan down a column into one that only
means something once you have read what produced it. Subsumed entities want their
own band beside that list rather than inside it.

### What that leaves the Emby view for

If subsumption works, the container view is complete — every file is reachable
from it — and the toggle stops being load-bearing. It is worth keeping anyway,
demoted from primary navigation to a second opinion: the Emby view is *what the
server will show*, which is the thing to look at when checking a projection, and
the two views computed from the same files disagreeing is exactly the signal that
an order has been authored but not yet applied — which is a thing worth drawing,
since it is the difference between a decision made and a decision carried out.

Three implementation notes survive that reframing:

- **The container view cannot be three columns.** Containers nest to whatever
  depth the show has — series → season → serial → episode for classic *Doctor
  Who*, series → episode for *The Prisoner* — so it wants an outline view with
  variable depth. The Emby view keeps its three columns, because Emby's model
  genuinely has three levels.
- **The view changes what is selectable, not what is editable.** Editing acts on
  whatever the selected entity owns, and ownership is already settled by the
  `nfo` pointer: a season edits `season.nfo` whether it was selected as a row in
  the Emby view or as a subsumed entity in the container view. Making edit rules
  depend on the view would be a second model of ownership to keep in step with
  the first.
- **The default is per series, not global.** A library part-way through this will
  have series with a `tvshow.smd` and series without, so the view that opens
  should follow the series. A global setting would be wrong for half the library
  whichever way it was set.

## Non-goals

- **Not a media database.** Cast, ratings, genres, provider ids and air dates
  stay in the NFO. If Emby has a field for it, the `.smd` does not. The shared
  database that would let a *pressing* be matched to a container, so that an
  `.smd` can be generated at ingestion rather than typed, is a separate
  proposal: `ContainerDatabase.md`.
- **Not a playback engine.** The format describes what exists and in what order;
  choosing a presentation for a given client is the player's decision.
- **Not a general graph.** One home per item. Refs, including refs across
  series, are positions in an order or entries in an extras list; they never
  give an item a second home.
- **Not a portable standard.** It is designed to degrade to a correct Emby
  library, not to be read by Emby, Jellyfin or Kodi. If it turns out to be
  useful elsewhere, that is a later conversation with a schema attached.

## Open questions

1. **Chapters inside an omnibus.** Named sequences settle where an omnibus
   *lives* — one item in a sequence of its own — but not how a client gets from
   it back to the parts. "Play part 3" from the omnibus needs chapter offsets
   mapping the one file onto the `parts` sequence, and a presentation currently
   names a file with no way to subdivide it. Deferred until a real omnibus with
   usable chapter stops is in the library; the two Dalek discs are the obvious
   test case.
2. **What makes an NFO "first".** No longer blocking — keeping the group in
   agreement means the answer cannot change the outcome — but still worth
   knowing, because an editor wants to label which sidecar Emby is actually
   reading, and it cannot do that from first principles. The test is two
   versions in a folder whose name order and creation order disagree. The same
   question applies to the group's thumb, which has not been measured at all and
   may not follow the NFO's rule.
3. **Whether a child can refuse to be exploded.** `exploded` is the parent's
   decision, which is right for a season of serials and wrong for a season that
   is flat apart from one two-part story worth keeping whole. A child veto is
   easy to add and easy to regret, and `type` may already carry the intent — a
   `serial` is a unit by definition, a bookkeeping `season` is not. Worth
   deciding from a real library rather than from first principles.
4. **camelCase.** NFO tags are lowercase and run together (`episodenumberend`,
   `airsbefore_season`). This proposal uses camelCase (`typeLabel`,
   `isolatedMusic`) deliberately, so a reader can tell at a glance which format a
   tag belongs to. The alternative is consistency with the sibling file.
5. **Hardlinking cross-series extras.** A `ref` into a companion series
   projects to nothing, which is correct and loses the extras row in Emby. A
   hardlink into the episode folder restores it at no storage cost, but the
   writer would then own a second NFO for the same file, and anything displaying
   them would have to know the two are one. Whether that is worth the machinery
   depends on how much the Emby view is still used once the container view
   exists.
6. **XML.** Chosen because the file sits beside NFOs and is hand-edited, so
   anything reading one is already parsing XML losslessly and can read the other
   with the machinery it has. JSON would be easier to emit and worse to read next
   to the file it accompanies.
