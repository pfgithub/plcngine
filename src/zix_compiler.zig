// replaceAll
// "%-" :: "ui.do(@src(), "
// "%[" :: ", {"
// "%]" :: "});"
// "%;" :: ", null});"

// "%s" ::
// "%[" :: "ui.InlineComponent.init(&__stack_0, @src(), struct{fn __anon_1(__stack_2: *Stack) {"
// "%]" :: "}}.__anon_1)"
// "%{" :: "{var __stack_0 = struct{...args} {...args}}"
// "%}" :: "}"
// "%(" :: "("
// "%)" :: ")"
//
// and then a fn is added outside:
// fn __anon_0(stack: *Stack) { ... }

// if we use the zig std tokenizer then we can make sure %s in strings and comments are ignored
