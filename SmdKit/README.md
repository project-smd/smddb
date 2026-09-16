<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the smddb project authors -->

# SmdKit

The parts of smddb that are not an app: the container model from
`Proposals/ContainerDatabase.md`, the file each container is kept as in the data repository, and
the interface a tool asks the database through. The macOS ingestion tool depends on it by path;
a validator for CI and, later, a service serving the same files are its other callers, which is
why it is a package of its own with no Apple-only dependency in it.

```sh
swift test
```

## What is here

- `Container` and the types under it — `Sequence`, `Entry`, `Alternative`, `Feature`,
  `ExternalRef` — are the sidecar proposal's elements as values, named as it names them.
- `ContainerFile` reads and writes one container as XML.
- `ContainerDatabase` is what a client asks: every container, one by id, the ones a provider's
  id names, and save. `roots()` — what nothing holds — is derived from those.
- `LocalRepository` is the phase 1 implementation: a folder that is a clone of the data
  repository.

Discs, releases and bindings are not here yet. They arrive with the identify and bind steps of
the ingestion flow, when their shape is known from use rather than from the proposal.

## The repository layout

`Hosting.md` says the one thing that is expensive to change is the repository layout, so it is
stated here rather than left implicit in the code.

**One file per container, at `containers/<id>.xml`.** The id is sixteen lowercase hex
characters — 64 random bits — minted when the container is created and never reissued, as the
database proposal specifies. Random rather than a slug because a slug has to be unique across
the whole database, which makes every "season-14" a negotiation, and because a path that
encodes the parent would change when the parent did. Random rather than sequential because
a clone of the repository mints ids without asking anyone. Sixteen characters rather than a
UUID because the corpus is thousands of files, not billions, and an id is read in refs and
file listings: at ten million containers the chance of any two colliding is about one in four
hundred thousand, and a collision is two files wanting one name, which a pull request shows.
The reader checks the shape and not the provenance, so any tool that draws sixteen hex
characters mints a valid id. A review reads the file's `<title>`, not its name. The id is also the root
element's `id` attribute, and a file whose two disagree is refused: the format's usual trade,
duplicate for legibility and verify mechanically.

**The file is the sidecar's `<container>` element with a library's facts taken out and the
database's put in.** Read against an `.smd`, the differences are exactly the ones the database
proposal lists:

| `.smd` | Repository file | Why |
| --- | --- | --- |
| `id="talons-of-weng-chiang"`, relative to the tree | `id="<16 hex>"`, global | Identity is minted here |
| `<item type="container" smd="Season 14/season.smd"/>` | `<item type="container" container="<16 hex>"/>` | A child is named by identity, not by where a library put it |
| `nfo="tvshow.nfo"` | `<externalRef provider="tvdb" value="76107"/>` | The NFO is where a library keeps the provider's id; here the id is the fact |
| `<presentation file="…">` | absent | Which file holds a thing is a library's fact |
| `<item ref="behind-the-sofa#s13-pyramids"/>` | `<item ref="<16 hex>#s13-pyramids"/>` | Same form, global id |

Everything else — titles, `year` (with `inTitle="true"` when the year is part of the name),
`typeLabel`, `outline`, `listed`, `<alternatives default="…">`,
`<features>`, `<sequence>`, `<item>`, `optional`, `<extras anchor="…">` — is spelled as the
sidecar spells it, so writing an `.smd` from one of these is a projection and not a
translation. Elements with no content are omitted; `listed` is written only when false.

A container's parent is not recorded on the container. It is derived: a container is a root
when no other container's item names it. That is one directory read, which principle 1 of the
database proposal keeps small.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<container format="1" id="6a1f0c2e-9b7d-4e3a-8f5c-1d2e3f4a5b6c" type="serial">
    <title>The Talons of Weng-Chiang</title>
    <typeLabel>Story</typeLabel>
    <externalRef provider="wikidata" value="Q3475469"/>
    <alternatives default="broadcast">
        <alternative id="broadcast" sequence="parts">
            <title>Broadcast version</title>
        </alternative>
    </alternatives>
    <features>
        <feature id="commentary1" type="commentary">
            <title>Commentary — Louise Jameson, John Bennett, Christopher Barry</title>
            <participant name="Louise Jameson" role="Leela"/>
        </feature>
    </features>
    <sequence id="parts">
        <item type="episode" id="part1">
            <externalRef provider="tvdb" value="1234"/>
        </item>
    </sequence>
</container>
```

`format="1"` is the version of this shape. The reader refuses a higher number rather than
half-reading it.
