> early development

```
zig build run
# (fix package if necessary)
zig bulid run
```

fix package: (this step will not be necessary after https://github.com/ziglang/zig/pull/16667 is merged)

```
cd ~/.cache/zig/p/12205138bd6276b716921d78586aa272d11dc9e848086fb9cb56f41f6be7869b466e
nvim build.zig
---
const std = @import("std");

pub fn build(b: *std.Build) !void {
    _ = b;
}
---
```

plcngine:

goals:

- engine/editor for pl¢tfarmer-style games

notes:

- instead of the infinite chunk world, we could make it so entities are placed arbitrarily
  in the world and you can draw on them. so an infinite world is a bunch of entities
  - and then layers are easy - entities
  - we have to figure out how to load the entities when they're needed
    - chunks with lists of entities that cover the chunk? + entities/<id>.plc_entity
- https://github.com/hexops/mach-examples/blob/main/examples/text2d/Text2D.zig
  - example of using a mach Atlas

todo:

- [x] build msdfgen ext/import-font.cpp (mach provides freetype)
- [x] move all libs from submodules to package manager
