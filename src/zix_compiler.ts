// consider using the zig stdlib tokenizer to support strings and at quote identifiers.
// that way strings like "%(hello%)" won't be messed up & identifiers like '%.@"hello"'
// will be supported.

import { PositionedError, prettyErrorHandle } from "./pretty_error";
function assert(cond: boolean): void {
  if(!cond) throw new Error("never");
}

class Tokenizer {
  constructor(
    public source: string,
    public srcloc: number = 0,
  ) {}

  readUntil(stop: string): string {
    let dest = this.source.indexOf(stop, this.srcloc);
    if(dest === -1) dest = this.source.length;
    const res = this.source.substring(this.srcloc, dest);
    this.srcloc = dest;
    return res;
  }
  readIf(msg: string): boolean {
    let startswith = true;
    for(let i = 0; i < msg.length; i++) {
      if(this.source[this.srcloc + i] !== msg[i]) {
        startswith = false;
        break;
      }
    }
    if(!startswith) return false;
    this.srcloc += msg.length;
    return true;
  }
  error(msg: string): never {
    throw new PositionedError("tkz", msg, this.srcloc, new TextEncoder().encode(this.source));
  }
  eof(): boolean {
    return this.srcloc >= this.source.length;
  }
  readRegex(regex: RegExp): RegExpMatchArray | null {
    let prevLastIndex = regex.lastIndex;
    regex.lastIndex = this.srcloc;
    const match = regex.exec(this.source);
    regex.lastIndex = prevLastIndex;
    if(match != null) {
      this.srcloc += match[0].length;
    }
    return match;
  }
}

const names = {
  state(id: number): string {
    return "_state_"+id;
  },
  fn(id: number): string {
    return "_fn_"+id;
  },
}

type TkzState = (
  | "fn_or_root"
  | "args"
  | "args_end"
);
let gid = 0;
function compileZix(source: Tokenizer, emit: string[]) {
  let state: TkzState = "fn_or_root";
  let args_tmp: null | string[] = null;
  let ids: number[] = [];
  while(!source.eof()) {
    emit.push(source.readUntil("%"));
    if(source.eof()) break;
    if(source.readIf("%(")) {
      if(state !== "fn_or_root") source.error("bad state");
      state = "args";
      if(args_tmp != null) source.error("args_tmp not equals null");
      args_tmp = [];
      emit.push("(");
    }else if(source.readIf("%)")) {
      if(state !== "args") source.error("bad state");
      state = "args_end";
      emit.push(")");
    }else if(source.readIf("%.")) {
      const res = source.readRegex(/[a-zA-Z0-9_]*/y);
      if(res == null || res[0] === "") {
        source.error("expected /[a-zA-Z0-9_]*/");
      }
      const resname = res[0];
      if(state === "fn_or_root") {
        let cid = ids[ids.length - 1];
        if(cid == null) source.error("not in cid context");
        emit.push(names.state(cid) + "." + resname + ".*");
      }else if(state === "args") {
        if(args_tmp == null) source.error("args_tmp equals null");
        emit.push(resname);
        args_tmp.push(resname);
      }else source.error("not in args or fn_or_root context");
    }else if(source.readIf("%{")) {
      if(state !== "args_end") source.error("bad state");
      state = "fn_or_root";
      const id = gid++;
      ids.push(id);
      emit.push("{");
      if(args_tmp == null) source.error("args_tmp equals null");
      emit.push("const "+names.state(id)+" = .{"+args_tmp.map(at => "." + at + " = &" + at).join(", ")+"};");
      args_tmp = null;
    }else if(source.readIf("%}")) {
      if(state !== "fn_or_root") source.error("bad state");
      emit.push("}");
      assert(ids.pop() != null);
    }else if(source.readIf("%[")) {
      const parent_id = ids[ids.length - 1];
      if(parent_id == null) source.error("parent_id is null");
      const id = gid++;
      ids.push(id);
      emit.push("ui.callback(&"+names.state(parent_id)+", ");
      emit.push("struct{fn "+names.fn(id)+"("+names.state(id)+": anytype) void {");
    }else if(source.readIf("%]")) {
      const sid = ids.pop();
      if(sid == null) source.error("ids empty");
      emit.push("}}."+names.fn(sid)+")");
    }else{
      source.error("percent nothing");
    }
  }
}

prettyErrorHandle("a.zix", () => {
  let out: string[] = [];
  compileZix(new Tokenizer(`
    fn Button%( %.item_one: []const u8, %.item_two: usize %) void %{
      VStack(%[
        std.log.info("value is: {d}, str: \"{s}\"", .{%.item_two, %.item_one});
      %]);
    %}
  `), out);
  console.log(out.join(""));
});
