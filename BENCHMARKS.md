# starwind benchmarks

`bench/bench.luau` times the package at what it is for: `build`, the whole Definitive build of a
sw_merged folder, strict and keeping its work. The real folder is the owner's (and most of it is
Bethesda's), so the bench builds one made up for it by `tests/corpus.luau`, the same every run:
the thirteen sources as tes3conv JSON, each with what the build does something to in its
namesake. Morrowind has objects of every type the build follows, the regions Starwind reuses,
cells that are read lazily and never read, and topics with their chains of INFOs for a speaker, a
race, a class, a faction, or anyone, some filtered on a global; Tribunal and Bloodmoon change,
move, add to, and delete from those topics. V1.15 has the main quest's anchors, its own objects,
actors, cells of references, and topics, and its hand in Morrowind's topics (an INFO copied
exactly, one copied but for its links, one changed, one deleted, a redundant and an orphaned
delete, and new ones, some said by an actor of Morrowind's nothing else names); the Patch and the
seven mods have more of the same over it; and every reviewed edit of the build has its target.
The folder is whole enough that the build of it passes every check the build makes, `--strict`
included.

- *the build* is 17,732 records in 13.8 MB of JSON, built into a monolith of 12,042 records
  (2.8 MB; 4,548 of them in Star_Data and 7,494 in Starwind), with 437 live topics holding 3,965
  of the masters' and the plugin's 5,454 INFOs, 22 late actors among 1,316, a decouple log of
  49,834 lines, and 7.5 MB of reports. Its line is the whole call, and the lines under it are
  the build's own stages as `options.timings` reports them, which between them are all of it.
- *the dialogue audit of that build, its INFOs drifted* is `dialogue.audit` over the same build
  with the INFOs of every sixth topic turned round in the plugin as written: 71 topics out of
  order, 2,114 inverted pairs to weigh one by one against the actors, 1,660 of them left
  unproven and traced to the sources. A build that passes never does this work; a build that
  fails does little else.

Each workload is warmed up and reported as the median of seven batches, with a full collection
between them: seven builds for the build, each stage the median of its seven, and for the audit
batches sized to about a tenth of a second. Before the batches and after them everything the
workload wrote (the three plugins, every report, the work files, and the manifest; the audit's
report) is hashed and has to come to the hash written in the bench, which is the baseline's: a
build that does less, or anything else, fails instead of posting a time.

```sh
jess run --package jpk/starwind --package-path jpk \
  --capability filesystem.read --capability filesystem.write \
  jpk/starwind/bench/bench.luau <scratch folder> [filter]
```

## The move onto l3i 2.0, base against head

- Machine: Intel Core i7-10870H @ 2.20 GHz, 16 threads, shared with other work while this ran.
- Date: 2026-10-12.
- Binary: the verified release build of Jess 0.1.0 the run measured with from 16:13 that day, on
  l3i's 2.0.2 tree (Luau 0.742), the same one for both sides, with the same `@tes3`,
  `@tes3conv`, `@merge-to-master`, and `@add-vanilla-refs` beside both.
- Base: `f15127a`, the package before the move, with the bench and its folder as they are now.
  Head: `2e5eebb`, the package after the move and its review.
- Protocol: the whole bench run against base, then head, three times over, back to back under one
  lock; each cell is the median of its three runs. A difference under 5 percent is called no
  change.

| Workload | Base | Head | Base / head |
|---|---:|---:|---:|
| the build of 17,732 source records | 2.124 s | 1.357 s | 1.56x |
| &nbsp;&nbsp;compile (`@tes3conv` reads the JSON) | 410.6 ms | 401.1 ms | no change |
| &nbsp;&nbsp;hygiene | 130.2 ms | 81.9 ms | 1.59x |
| &nbsp;&nbsp;preprocess (two guard checkpoints, the reviewed edits) | 49.0 ms | 23.7 ms | 2.07x |
| &nbsp;&nbsp;merge (`@merge-to-master`, a guard checkpoint) | 77.1 ms | 75.3 ms | no change |
| &nbsp;&nbsp;decouple (`@add-vanilla-refs`) | 136.3 ms | 133.1 ms | no change |
| &nbsp;&nbsp;write (`@tes3conv` encodes the plugins) | 192.3 ms | 201.5 ms | no change (0.95x) |
| &nbsp;&nbsp;read back (`@tes3`, `@tes3conv`) | 54.8 ms | 47.4 ms | 1.16x, see below |
| &nbsp;&nbsp;closure | 39.9 ms | 23.2 ms | 1.72x |
| &nbsp;&nbsp;dialogue audit | 267.6 ms | 39.1 ms | 6.84x |
| &nbsp;&nbsp;late actors | 362.7 ms | 89.9 ms | 4.03x |
| &nbsp;&nbsp;split | 387.3 ms | 215.6 ms | 1.80x |
| &nbsp;&nbsp;manifest | 1.3 ms | 1.3 ms | no change |
| the dialogue audit of that build, its INFOs drifted | 1.980 s | 199.3 ms | 9.93x |

This is the review's run. The run the move was first recorded from, against `d432f75`, came to
the same: the build 2.107 s to 1.363 s (1.55x), the drifted audit 1.941 s to 191.9 ms (10.11x),
and each of the six stages that moved within 4 percent of its ratio here. A third run, the two
sides once a round among other commits, came to 2.196 s and 1.330 s (1.65x), and 1.935 s and
185.9 ms (10.41x).

The read-back row is not a gain. It has read 1.16x or 1.17x in all three runs, and in all three
the write stage before it has read 2 to 6 percent slower: the two together are 247 ms at base
and 249 ms at head here. Nothing in either changed but two `table.remove` calls that became
slices, which are well under a millisecond either way, and the rest of both stages is
`@tes3conv`'s. Which side of the stage boundary the collector's work falls on is the likeliest
reading, and it was not chased further.

None of it is the dialect, and none of it is the data plane. A build is strings and record
tables: there is no column of numbers in it to hand to `@dream/data`, and the comprehensions,
reducers, slices, and record patterns the package now uses lower to the loops they replaced. What
moved the numbers was work the build no longer does, found by profiling it. Each change, in the
stage it is in, as it was first measured and as the review measured it again (the median of three
runs of the bench against that commit over the median of three against the commit before it,
every commit once a round, each round under the lock):

| Change | Stage | First | Again |
|---|---|---:|---:|
| `326c578` the actors two INFOs share counted once a pair, what each asks read once and asked only of the actors it names | drifted audit | 3.67x | 3.71x |
| `384bbb3` two records told to be the same before either is copied or its fields put in order | dialogue audit | 6.33x | 6.79x |
| | drifted audit | 1.67x | 1.64x |
| `95fcab3` a field's name spelled in snake_case once | late actors | 1.26x | 1.32x |
| `521565b` the log's copy lines matched only where a line says Copying | late actors | 1.06x | 0.94x, in a round where every stage read 0.92x to 0.95x |
| `84e5a12` the path to a value spelled only when it names a late actor, and each string looked up once | late actors | 2.53x | 2.71x |
| `1fdc2ab` the INFOs each late actor says found in one walk of the projection | late actors | 1.15x | 1.17x |
| `508595d` each string a report holds spelled once an encode | hygiene | 1.58x | 1.60x |
| | split | 1.20x | 1.19x |
| `c91f53f` a record's dependencies read with no closure made and no kind spelled | closure | 1.49x | 1.07x |
| | split | 1.14x | 1.04x |
| `f653cfd` the split's keys kept as the types under each id | split | 1.12x | 1.26x |
| `0707ecf` each record's dependencies read once a validation | split | 1.17x | 1.24x |
| `4c0daff` the junk cells deleted in one walk of each plugin | preprocess | 1.25x | 1.24x |
| `ac7a36a` only the anchors marked at a checkpoint | preprocess | 1.74x | 1.75x |
| | closure | 1.52x | 1.39x |
| `1da40fb` a script's lines read only when it says AddTopic | dialogue audit | 1.08x | 1.05x |
| `3e3deb0` what two INFOs share asked of the actors of a race or a class | drifted audit | 1.15x | 1.14x |

A stage of a few tens of milliseconds wanders by a tenth between two commits that don't touch it,
so a row is good for the stage it names and no further, and three rows are at the edge of what
the bench can tell or past it. Those were timed by themselves, the old code beside the new over
the bench build's own data, the median of seven batches, three times:

- `521565b`: reading the copy lines out of the 49,834-line log, 17.3 ms to 4.5 ms (3.9x), the
  same 461 copies found. That is 13 ms of a late-actor stage that was about 300.
- `1da40fb`: reading the build's 279 scripts for the topics they add, 3.8 ms to 0.95 ms (4.0x),
  40 of them saying AddTopic and the same 16 topics found. That is 3 ms of a 44 ms stage.
- `c91f53f`: `dependencies.of` over 16,278 of the folder's records, 37.3 ms to 23.6 ms (1.58x),
  the same 39,597 dependencies. The closure stage walks the build's records once and the split's
  validation walked them in four passes; the stage ratios put its gain in the closure stage on
  the commit after it, which touches nothing that stage runs, and across the two together that
  stage is 1.27x here and was 1.30x when first measured.

The dialect commits are no change, and neither are the review's. From `3e3deb0`, the last change
made for speed, to head: the build 1.363 s to 1.330 s (1.03x) and no stage past 3 percent but
the 23 ms closure. The drifted audit over five rounds is 179.3 ms and 187.7 ms (0.96x), and all
of that is there by `546cefe`, four commits that touch nothing the audit runs; the commit that
turns the audit's own loops into comprehensions, `59031d7`, is 187.1 ms against 186.8. An audit
writes its whole report as one string every call, and a workload that does that moves with the
layout of the heap. The review put seven comprehensions back as loops (each read a list a caller
hands in, which a loop walks past a gap in and a comprehension raises for); none is on a hot path
and head against the head before them is 187.7 ms against 187.9.

A command that runs once pays for loading the package, which the bench's warm calls don't show.
`starwind help`, which loads every module and builds nothing, over 31 cold runs a side, the sides
by turns: 228.9 ms at base, 234.0 ms at `3e3deb0`, 236.0 ms at head. That is 0.97x and inside the
5 percent, but it leans the same way at the minimum and the maximum: about 5 ms for the modules
being larger and 2 ms for the dialect, against the 770 ms a build no longer takes.

Three things were most of it. The dialogue audit compared every INFO it expected with the one
written by making a copy of each without its links, listing the two records' fields, and sorting
that list with a comparison that spelled both names in snake_case each time it was asked; nearly
every pair is the same, which a walk of the two tells with nothing made. The late-actor scan made
a table and a dotted path for every value of every record of the build and of five sources, to
look a handful of ids up among them; now a path is spelled for a hit. And the weighing of an
inverted pair of INFOs asked every actor in turn whether both could be its speaker, lowering
both INFOs' four constraints again for each actor, twice over for a pair it couldn't prove
harmless.

What is left of a build is mostly not this package's: reading the JSON, `@merge-to-master`'s
nine merges, `@add-vanilla-refs`, and writing and reading the plugins are 858 ms of the
1,357, and were 871 of the 2,124. The package's own stages went from 1,238 ms to 475. Of those,
the split is nearly half: it writes two plugins and reads them back, and its report alone is 3.8 MB of
JSON that names every dependency of Starwind on Star_Data.
