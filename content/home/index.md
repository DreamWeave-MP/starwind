+++
title = "starwind"
description = "Builds Starwind, the Star Wars total conversion, from its sources on a Morrowind install, as a Jess command in Luau."
date = 2026-10-21

[taxonomies]
tags = ["Jess", "Luau", "OpenMW"]

[extra]
sections = ["overview", "releases", "credits"]
+++

Builds Starwind, the Star Wars total conversion, from its sources on a Morrowind install, as a Jess command in Luau.

<!-- more -->

A [Jess](https://github.com/DreamWeave-MP/jess) package, `org.dreamweave.starwind`. Add it to a `jess.toml` and
`jess workspace sync` pins it from this site:

```toml
[dependencies]
"org.dreamweave.starwind" = "0.1"
```

Every release below is the package's own archive, with its content digest beside the archive's
SHA-256; `jess.lock` pins the first and checks both.
