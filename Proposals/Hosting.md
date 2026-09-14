<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the smddb project authors -->

# Hosting

**Status:** proposal. Nothing here is implemented, and nothing here has been
measured. Depends on `ContainerDatabase.md`, whose store this serves, and
replaces the sketch in its *Hosting and licence* section.

Where the data lives, what serves it, and how a binding gets from a disc in
somebody's drive to a row everyone else can read.

## The problem

Three requirements that look like three systems: a read API, somewhere to keep
the data, and a way to accept, vet and approve contributions. The third is
normally where the budget goes — authentication, roles, a submission queue, a
moderation UI, an audit log, spam handling, rollback — and none of it is the
thing this project is about.

Two facts about the workload make an unusual answer available.

**The store is small by construction.** `ContainerDatabase.md` keeps the
semantic layer only: a DiscTitle exists just while a binding points at it, and
menus, logos and play-all titles are never rows. That is what keeps this out of
TheDiscDb's 258,880-playlist territory. Tens of thousands of rows, single-digit
megabytes, and it grows at the rate people rip discs.

**Reads vastly outnumber writes, and the hot read is content-addressed.** Step 2
of the ingestion flow is a disc fingerprint looked up by exact key. The answer
for a given fingerprint changes only when someone contributes a binding for that
pressing.

A store that small, read that way, written that rarely, does not need a database
server. It needs a build.

## Principles

1. **The contract is a specification, not an artifact.** Whatever is published
   is what future refactors have to preserve. Publish a versioned API and the
   file layout, the shard scheme and the schema stay ours to change; publish the
   files and every column name is public interface.
2. **Git is the store; the served database is a build output.** One direction
   only. Nothing writes to the served copy, so it has no migrations, no backup
   story of its own, and no way to diverge from the source.
3. **Most review is mechanical.** The validation pass in `StructuredContainers.md`,
   referential integrity across `ExternalRef`, and principle 4's rule that
   TheDiscDb's labels are checked against the provider before they are believed
   are all jobs a machine does. Human judgement is for ambiguous bindings, and
   should not be spent on anything else.
4. **The workflow is behind the API too.** A contributor's tool learns
   contribution *states*, never pull requests. That is what lets the review
   mechanism be replaced without touching a client.
5. **One model, not three.** The `.smd` schema, the database schema and the API
   types are three expressions of the same thing, and three is how a one-model
   design quietly becomes a three-vocabulary one.

## Where the data lives

A public git repository, one file per container and one per disc.

Sharding by entity is the part to get right on the first commit, because it is
painful to retrofit once history exists. One file per entity means a
contribution touches one file, two contributions rarely conflict, and a review
is a diff a person can actually read. A monolithic export means every
contribution conflicts with every other and no review is legible.

What the repository supplies, for nothing, is the whole of requirement three:
identity, discussion, diffs, an audit trail better than one we would write,
rollback, and rate limiting. Building that on top of a live database is the bulk
of the work, and all of it is undifferentiated.

**Where this stops working** is worth naming now. Git as a store fails when
review throughput becomes the bottleneck — when contributions arrive faster than
humans merge them — or when the repository grows past the point where cloning it
is a nuisance. The row-count constraint in principle 1 of the database proposal
is what holds both of those off, and it is a constraint rather than a hope: if
that ever relaxes, this proposal is what should be revisited first.

## What serves it

On merge: validate, build a SQLite database from the repository, bake it into a
container image, deploy the image. The service reads that file and nothing else.

**The data is part of the deployment artifact.** That single decision removes
most of the operational surface. There is no runtime migration, because the
schema ships with the code that reads it. There is no consistency question,
because nothing writes. Deploying is an atomic swap, and rolling back is
redeploying the previous image — which rolls back the data and the code
together, since a bad merge and a bad build are the same kind of accident.

It costs one thing: image size grows with the data, and at some point baking a
database into an image stops being sensible. At single-digit megabytes that is
years away, and the point at which it bites is measurable rather than a matter
of opinion — so measure it rather than pre-empt it.

**Cache responses, not files.** A fingerprint lookup is immutable between
builds, so responses carry a long TTL and an ETag stamped with the build id, a
CDN sits in front, and the cache is purged on deploy. That recovers the edge
performance of serving static files without making the files the contract.

## The read API

OpenAPI, versioned under `/v1`, and the spec checked against the implementation
in CI — a spec that drifts from the service is worse than none, because it is
believed.

The contract is already written, in principle 2 of the database proposal: *an
`.smd` is what a client gets when it asks for one container; the database is
what it asks.* So the API serves one model in the two serialisations that
already exist, and invents no third vocabulary for transport:

| Route | Answers |
| --- | --- |
| `GET /v1/discs/{fingerprint}` | What is on this disc — the ingestion lookup, and the hot path |
| `GET /v1/containers` | Everything a person can browse to — listed containers only |
| `GET /v1/containers/{id}/companions` | Companion series of this one, listed or not. The only route to an unlisted container, which is what makes `listed` mean something |
| `GET /v1/containers/{id}` | The container as JSON |
| `GET /v1/containers/{id}.smd` | The same container as a sidecar, ready to write beside the files |
| `GET /v1/entries/{id}/discs` | Which pressings carry this entry, in which cut, with chapter spans |
| `GET /v1/features/{id}/discs` | Which pressings carry this commentary, with stream indices |
| `GET /v1/lookup?provider=tvdb&value=…` | The entry or container a provider id resolves to |
| `GET /v1/exports/{version}` | The bulk export, by redirect to object storage |

The endpoint list should follow the *Questions the model answers* table in the
database proposal rather than being invented alongside it. That table is the
argued statement of what this store is for; an endpoint with no question behind
it is a guess about a client nobody has written yet.

## The contribution path

```
POST /v1/contributions      → 202, { id, state: "pending" }
GET  /v1/contributions/{id} → { state, notes[] }
```

States are `pending`, `changes-requested`, `merged` and `rejected`. A client
never learns that a pull request exists. Replacing pull requests with a queue and
a reviewer app later changes nothing a contributor's tool depends on, which is
the whole point of putting the workflow behind the API rather than pointing
people at a repository.

Three decisions inside that are worth making deliberately.

**The DCO sign-off is captured at submit, and this is the one that cannot be
retrofitted.** If the service opens pull requests under a bot account, the
contributor's identity and consent are not on the commit unless we put them
there. So the submission carries the contributor's identity and the licence
version they agreed to, the service records both with the contribution, and the
commit it produces carries them as trailers. Get this wrong and the result is a
dataset that cannot be relicensed and whose provenance cannot be shown — and the
people whose consent would be needed are, by then, unreachable. It follows
directly from settling CC BY 4.0 against CC0 before the first row, not after.

**Submissions are idempotent.** A ripping tool that retries after a timeout must
not open a second pull request. Either a client-supplied idempotency key or a
content hash of the submission, resolving to the contribution already created.

**Validation runs in two stages.** The cheap checks — schema, referential
integrity, a well-formed fingerprint — run synchronously at submit, so the tool
gets a 400 with a reason while the disc is still in the drive. The expensive
ones — provider cross-checks, the full validation pass — run in CI on the
resulting branch. The same validation library serves both callers, because two
implementations of one rule set is how a submission comes to pass one gate and
fail the other.

## Bulk export

Artifact-shaped, and honest about being an artifact: a documented, versioned dump
in object storage, not an interface pretending to be a file. It is the
disaster-recovery story, and it is the reason the data survives this project —
a store whose only copy is the one being served is a store that can disappear.

Egress is the one cost line this project can plausibly run into, because a public
dataset that is exported wholesale and regularly is exactly the shape that gets
charged for. Object storage without egress fees is worth more here than a cheaper
per-gigabyte rate.

## Choosing a provider

The reframe makes this a low-stakes decision, which is itself the most useful
thing to say about it: the source of truth is a repository, the served thing is a
build artifact, and moving between providers is an afternoon. Nothing below is
load-bearing enough to agonise over.

- **Repository, review and CI: GitHub.** The workflow is the product here, not
  the hosting.
- **Service: a scale-to-zero container platform** — Cloud Run or Fly.io. A
  bundled native SQLite wants a container rather than an edge function, and
  scale-to-zero suits a service whose traffic is a few lookups per rip.
- **Exports: object storage without egress fees**, for the reason above.

**The case for AWS**, honestly: an account that already has billing, alarms and
deployment habits has near-zero marginal cost for one more service, and that is
real money in evenings-and-weekends time. What it costs is ceremony — IAM,
infrastructure-as-code, a pipeline — around something whose essential complexity
is "build a file, ship it in an image, answer queries from it". For a project
whose scarce resource is attention rather than throughput that is the wrong
trade, but it is a preference rather than a mistake, and principle 2 makes it
reversible.

**The case against edge platforms**, given this design: bundling a native SQLite
does not fit them, and their managed alternatives reintroduce exactly the
stateful thing the build was supposed to remove — something to migrate, keep in
sync, and back up.

**The case for one boring VPS:** it removes the artifact-building indirection
entirely, and a machine that would handle this a thousand times over costs less
than lunch. The price is owning patching, backups and monitoring for a service
that takes a handful of writes a day.

Every option here is free or nearly free at this size, so the decision is about
operational burden and lock-in, not money. Free-tier terms move; check them
rather than trusting this paragraph.

## Non-goals

- **Not a live-write database.** Writes go through review. When that stops being
  true, the API is already the seam that lets it change.
- **Not a moderation UI.** The forge's own review tools are the moderation UI
  until the volume justifies otherwise.
- **Not a general query endpoint.** No GraphQL, no ad-hoc filters: the questions
  the model answers are the API, and a general query surface would make the
  schema public interface by the back door — the same mistake as publishing the
  files.
- **Not highly available.** The service is stateless and rebuildable from the
  repository; a deploy that fails rolls back to the previous image. Multi-region
  is not a problem this project has.

## Open questions

1. **Whether contributions are attributed on the commit.** A bot-opened pull
   request keeps the abstraction total but puts the contributor's name only in
   the metadata we record. Authorising through the forge as the contributor puts
   it on the commit, at the price of leaking the mechanism into the client. The
   DCO capture above makes either defensible; which reads better to a
   contributor is a judgement, not a deduction.
2. **When baking the database into the image stops fitting.** Measurable, and
   worth measuring at the first thousand discs rather than guessing now.
3. **Whether the OpenAPI document is generated from the schema or written and
   checked against it.** Generation keeps principle 5 honest for nothing;
   hand-writing usually produces a better-documented API. A check in CI is the
   minimum either way.
4. **Rate limiting and abuse handling on the contribution endpoint**, which has
   to exist before the endpoint is public, and which the repository was quietly
   providing while contributions arrived as pull requests.
