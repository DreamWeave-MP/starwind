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
- Binary: the verified release build of Jess 0.1.0 on l3i 2.0.1 (Luau 0.742), the same one for
  both sides, with the same `@tes3`, `@tes3conv`, `@merge-to-master`, and `@add-vanilla-refs`
  beside both.
- Base: `f15127a`, the package before the move, with the bench and its folder as they are now.
  Head: `d432f75`.
- Protocol: the whole bench run against base, then head, three times over, back to back under one
  lock; each cell is the median of its three runs. A difference under 5 percent is called no
  change.

| Workload | Base | Head | Base / head |
|---|---:|---:|---:|
| the build of 17,732 source records | 2.107 s | 1.363 s | 1.55x |
| &nbsp;&nbsp;compile (`@tes3conv` reads the JSON) | 403.2 ms | 412.3 ms | no change |
| &nbsp;&nbsp;hygiene | 130.0 ms | 83.6 ms | 1.55x |
| &nbsp;&nbsp;preprocess (two guard checkpoints, the reviewed edits) | 49.1 ms | 24.3 ms | 2.02x |
| &nbsp;&nbsp;merge (`@merge-to-master`, a guard checkpoint) | 77.0 ms | 76.4 ms | no change |
| &nbsp;&nbsp;decouple (`@add-vanilla-refs`) | 136.0 ms | 131.1 ms | no change |
| &nbsp;&nbsp;write (`@tes3conv` encodes the plugins) | 192.7 ms | 203.3 ms | no change |
| &nbsp;&nbsp;read back (`@tes3`, `@tes3conv`) | 55.0 ms | 47.6 ms | 1.16x |
| &nbsp;&nbsp;closure | 42.3 ms | 24.5 ms | 1.73x |
| &nbsp;&nbsp;dialogue audit | 264.0 ms | 40.0 ms | 6.59x |
| &nbsp;&nbsp;late actors | 355.8 ms | 91.4 ms | 3.89x |
| &nbsp;&nbsp;split | 389.5 ms | 222.5 ms | 1.75x |
| &nbsp;&nbsp;manifest | 1.4 ms | 1.6 ms | no change |
| the dialogue audit of that build, its INFOs drifted | 1.941 s | 191.9 ms | 10.11x |

None of it is the dialect, and none of it is the data plane. A build is strings and record
tables: there is no column of numbers in it to hand to `@dream/data`, and the comprehensions,
reducers, slices, and record patterns the package now uses lower to the loops they replaced. What
moved the numbers was work the build no longer does, found by profiling it:

| Change | Build | Hygiene | Preprocess | Closure | Dialogue audit | Late actors | Split | Drifted audit |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `326c578` the actors two INFOs share counted once a pair, what each asks read once and asked only of the actors it names | 1.07x | 1.04x | 1.08x | 1.04x | 1.05x | 1.06x | 1.10x | 3.67x |
| `384bbb3` two records told to be the same before either is copied or its fields put in order | 1.11x | 0.99x | 0.99x | 1.07x | 6.33x | 1.02x | 0.99x | 1.67x |
| `95fcab3` a field's name spelled in snake_case once | 1.06x | 1.02x | 0.97x | 0.93x | 0.95x | 1.26x | 0.97x | 1.06x |
| `521565b` the log's copy lines matched only where a line says Copying | 1.01x | 1.02x | 1.02x | 1.01x | 0.98x | 1.06x | 1.05x | 0.99x |
| `84e5a12` the path to a value spelled only when it names a late actor, and each string looked up once | 1.07x | 1.00x | 1.00x | 0.83x | 0.98x | 2.53x | 0.97x | 1.03x |
| `1fdc2ab` the INFOs each late actor says found in one walk of the projection | 1.01x | 0.99x | 0.97x | 1.03x | 1.00x | 1.15x | 0.99x | 0.97x |
| `508595d` each string a report holds spelled once an encode | 1.08x | 1.58x | 1.05x | 1.10x | 1.02x | 1.00x | 1.20x | 1.42x |
| `c91f53f` a record's dependencies read with no closure made and no kind spelled | 1.04x | 0.97x | 1.03x | 1.49x | 1.05x | 0.98x | 1.14x | 0.99x |
| `f653cfd` the split's keys kept as the types under each id | 0.98x | 0.98x | 0.88x | 0.87x | 0.96x | 1.00x | 1.12x | 0.97x |
| `0707ecf` each record's dependencies read once a validation | 1.04x | 0.93x | 1.01x | 0.95x | 0.95x | 0.95x | 1.17x | 0.99x |
| `4c0daff` the junk cells deleted in one walk of each plugin | 1.00x | 1.02x | 1.25x | 0.98x | 1.06x | 1.03x | 1.06x | 1.03x |
| `ac7a36a` only the anchors marked at a checkpoint | 1.05x | 1.10x | 1.74x | 1.52x | 0.99x | 1.03x | 0.98x | 1.03x |
| `1da40fb` a script's lines read only when it says AddTopic | 0.97x | 0.93x | 0.96x | 0.93x | 1.08x | 0.97x | 0.93x | 0.96x |
| `3e3deb0` what two INFOs share asked of the actors of a race or a class | 1.02x | 1.02x | 1.04x | 0.99x | 0.97x | 1.02x | 1.09x | 1.15x |
| the eight dialect commits after it, together (`ea2b76c` to `0c07e66`) | 1.00x | 0.99x | 0.99x | 1.06x | 1.10x | 1.00x | 0.92x | 0.98x |

Each cell there is the median of three runs of the bench against that commit over the median of
three against the commit before it, the sixteen commits run one after another once a round, each
round under the lock. Read a row for the stages its change is in and no further: a stage of a few
tens of milliseconds wanders by a tenth between two commits that don't touch it (the closure
stage is 0.83x in a row that changes nothing near it, and the split is anywhere from 206 to
226 ms over the four commits after `0707ecf`, none of which touches it), so `521565b`'s 1.06x and
`1da40fb`'s 1.08x are at the edge of what this bench can tell. The dialect commits are no
change: the build run again against `3e3deb0` by itself, four rounds, came to 0.99x, with the
split at 0.99x and the dialogue audit at 1.00x. The guard's checkpoints run inside the
preprocess, merge, and closure stages, which is why `ac7a36a` moves two of them. The first table
is the measurement.

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
nine merges, `@add-vanilla-refs`, and writing and reading the plugins are 871 ms of the
1,363, and were 864 of the 2,107. The package's own stages went from 1,232 ms to 488. Of those,
the split is nearly half: it writes two plugins and reads them back, and its report alone is 3.8 MB of
JSON that names every dependency of Starwind on Star_Data.
