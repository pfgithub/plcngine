> early development

```
git submodule update --init --recursive
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
