<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the smddb project authors -->

# Roadmap

**Status:** a plan rather than a design. The other three documents say what to
build; this says in what order, what each phase has to prove before the next one
starts, and which decisions have deadlines attached.

## The ordering principle

Only one thing here is genuinely expensive to change: the repository structure
and the schema. History accumulates behind them, contributions reference each
other, and a rename after a hundred merges is an archaeology project. Everything
else — the service, the platform, the queue, the API surface — is replaceable in
an afternoon, which is what the whole of `Hosting.md` was arranged to guarantee.

So the schema goes first and is pressure-tested by hand, before any
infrastructure exists that would make changing it awkward.

The second rule is that **each phase has to be useful on its own**, not merely a
step toward the next one. A phase whose only value is unlocking the following
phase is a phase that gets abandoned during a busy fortnight.

## Phase 1 — one tool, one user, no infrastructure

A macOS ingestion tool that reads a disc and writes to a local clone of the
repository. No API, no authentication, no queue, no deployment, no server. The
contribution mechanism is a commit.

The flow it automates is steps 1 to 5 of the ingestion flow in
`ContainerDatabase.md`: MakeMKV robot info, fingerprint, identify, bind, rip,
write. Two things about its output matter more than they look.

**It generates the `.smd` and files it into the library.** Principle 2 of the
database proposal claims that the database and the sidecar are one model, and
right now that claim is a correspondence table in a document. Generating one
from the other is what makes it true or exposes where it is not, and finding
that out on the third disc costs nothing where finding it out on the fiftieth is
a migration.

It is also what makes the tool **selfishly useful**. If the output of phase 1 is
data entry toward a public good that does not exist yet, it will rot during the
first busy week. If the output is that your own library gains serials, alternate
cuts and described commentaries that Emby could not otherwise express, it earns
its keep on the first disc and keeps earning it.

**The validator ships here**, crudely, and CI runs it from the first commit —
while the only person it can annoy is the person who wrote it. It has three
callers eventually: this tool, CI, and the synchronous submit check in phase 3.
Writing it later means discovering that fifty committed files are subtly wrong
and fixing history rather than fixing code.

### One box, and the story to start with

Twenty straightforward box sets would produce twenty rows that prove nothing and
a schema that breaks on the twenty-first. The target is **Season 13 of the
classic series on Blu-ray**, chosen because a single purchase exercises more of
the model than a shortlist of separately-bought discs would.

Six serials, 26 episodes: *Terror of the Zygons* (4), *Planet of Evil* (4),
*Pyramids of Mars* (4), *The Android Invasion* (4), *The Brain of Morbius* (4)
and *The Seeds of Doom* (6). On top of that the box carries omnibus editions of
Pyramids, Morbius and Seeds; updated special effects on Zygons and Pyramids; a
director's cut of Zygons part one only; commentaries on every story, some parts
carrying a second Tom Baker solo track; six *Behind the Sofa* instalments, one
per story; and a *Tales of the TARDIS* cut of Pyramids.

**Start with Pyramids of Mars.** It is the whole format in one story:

| Structure | Where it appears in Pyramids |
| --- | --- |
| Multi-part sequence | The four broadcast parts |
| A second sequence | The omnibus edition |
| Alternative over the parts | Updated special effects |
| Alternative over its own sequence | The omnibus |
| Feature spanning every part | Commentary 1, four participants |
| Feature over a subset | Commentary 2 — Tom Baker, parts 1 and 3 — whose run is derived, not declared |
| Track mapping per presentation | Both commentaries on the broadcast files *and* the SE files, with stream indices that need not match |
| Cross-series ref, with external identity | *Tales of the TARDIS*, listed, its home in its own series |
| Cross-series ref, without | *Behind the Sofa*, unlisted, reachable only through this series |

Everything in the format except chapter spans, in one story. If the schema
survives Pyramids the rest of the season is repetition, which is exactly what you
want from a first target — and what makes it the natural fixture to write the
validator's tests against.

Two things the season leaves untested, to be picked up afterwards: **chapter
spans**, which want a DVD title holding several episodes, and **a box mixing
formats**, which is what Release and Disc are kept separate for. *The Daleks in
Colour* covers both and is the obvious follow-up.

The awkward case the box will force a decision on: **an omnibus cannot be
projected to Emby at all.** One file covering four episodes has no expression in
its model, so the `.smd` can describe it and Emby cannot see it. Ignore it, file
it as an extra, or make it a special — decide during phase 1 rather than after.

**Phase 1 ends** when the schema has survived several consecutive ingests
without changing, and the generated `.smd` is what your library actually runs
on.

## Phase 2 — the read path, over data that exists

Now there is something to read, so the endpoint list can be derived rather than
imagined.

**The build comes first**: repository → validate → SQLite → deployable artifact.
This is where the pipeline in `Hosting.md` gets written, and it is the thing
every later phase depends on.

**Then HTML, before the API.** They are two products and doing both at once
doubles the phase. The site falls out of the same build, and its first job is
being how you look at the data you spent phase 1 entering — a debugging tool for
the previous phase that happens to become the public face of this one.

**Then the API**, following the *Questions the model answers* table rather than
growing alongside it. An endpoint with no question behind it is a guess about a
client nobody has written.

**Then publish the bulk export**, which is both the disaster-recovery story and
the cheapest possible test of whether anyone else wants this at all.

The platform decision belongs at the end of this phase, not the start, and the
design is arranged so that it stays a decision about ergonomics rather than
capability.

**Phase 2 ends** when every question in that table can be answered from the
built artifact, and inspecting the data through the site is easier than opening
the files.

## Phase 3 — contributions from people who are not you

Gated on evidence rather than on the calendar. The export from phase 2 is the
test: if nobody is pulling it, nobody is waiting to contribute either, and
building a contribution API is a bet on contributors who do not exist.

When it does start, the order inside the phase is:

1. **Identity** — federated login, no passwords, no account management.
2. **A synchronous submit path**, with the forge as the queue: validate, create
   the pull request, return its number as the contribution id, poll the forge
   for state. Nothing stateful of your own.
3. **Rate limits** — crude at the edge, per-identity in the application.
4. **Trust tiers and corroboration**, which is what stops human review becoming
   the bottleneck: auto-accept when validation passes and a second independent
   submission of the same fingerprint agrees; review when it passes but nothing
   corroborates; reject with a reason, synchronously, when it fails.
5. **A queue, only once the synchronous forge call has demonstrably become the
   problem.** The `202`-plus-poll contract makes adding one invisible to every
   client, which is precisely why it can wait.

**Phase 3 ends** when somebody who is not you has contributed a binding that
nobody had to fix.

## Decisions with deadlines

Several open questions are not urgent but do have a point past which they get
expensive. Recording when, rather than treating them all as pending:

| Decision | Deadline | Why then |
| --- | --- | --- |
| TheDiscDb attribution | First commit that ingests its data | MIT terms arrive with the data whatever licence you eventually pick for your own |
| Whether to contribute upstream to TheDiscDb instead | During phase 2 | If it would carry an `EntryId`, phase 3 shrinks substantially. Have the conversation when there is real data to show and before building what it might obviate |
| Read platform | End of phase 2 | Deliberately late. Nothing before this needs it decided |
| ~~Data licence — CC BY 4.0 or CC0~~ | Decided, September 2026 | CC0 1.0, in `project-smd/data`. See the licence section of `ContainerDatabase.md` for the grounds |
| ~~DCO capture, and where the consent record lives~~ | Decided, September 2026 | A per-commit sign-off against the data repository's own certificate, in its `CONTRIBUTING.md`. The record is the git history, which forks with the data |
| Contributor attribution — bot-opened pull requests or authorised as the contributor | Before the contribution API ships | It decides how exposed the choice of forge is, and therefore how much the platform-dependence question matters |

## The risk this plan is managing

One failure mode, and every phase boundary is a checkpoint against it: building
infrastructure for a dataset that does not exist yet and contributors who never
arrive.

Phase 1 is useful to one person with no infrastructure at all. Phase 2 is useful
to anyone with a browser, and still has no contribution path. Phase 3 happens
only on evidence that someone is waiting for it. If the project stops after any
one of them, what exists still works and still has a reason to exist — which is
the only real defence against a design this thorough being built in the wrong
order.
