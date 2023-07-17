const State = struct {
    start_pos: ?Vec2i,
};
const Config = struct {
    width: i32,
};

const Tool = struct {
    config: Config,
    state: State,
};

// export common interface