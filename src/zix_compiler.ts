// consider using the zig stdlib tokenizer to support strings and at quote identifiers.
// that way strings like "%(hello%)" won't be messed up & identifiers like '%.@"hello"'
// will be supported.

import {readdirSync, statSync} from "fs";
import * as path from "path";
import { PositionedError, prettyDisplayError, prettyErrorHandle } from "./pretty_error";
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
  error(msg: string, srcloc: number | null = null): never {
    throw new PositionedError("tkz", msg, srcloc ?? this.srcloc, new TextEncoder().encode(this.source));
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
  state_ty(id: number): string {
    return "_State_"+id;
  },
  fn(id: number): string {
    return "_fn_"+id;
  },
}
function name(a: string, b: number): string {
  return "_" + a + "_" + b;
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
  let id_srclocs = new Map<number, number>();
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
        emit.push("_fn_arg_", resname);
        args_tmp.push(resname);
      }else source.error("not in args or fn_or_root context");
    }else if(source.readIf("%{")) {
      if(state !== "args_end") source.error("bad state");
      state = "fn_or_root";
      const id = gid++;
      id_srclocs.set(id, source.srcloc);
      ids.push(id);
      emit.push("{");
      if(args_tmp == null) source.error("args_tmp equals null");
      emit.push("var _usr_data: usize = 0;");
      emit.push("const "+names.state(id)+" = .{._usr = &_usr_data, "+args_tmp.map(at => "." + at + " = &_fn_arg_" + at).join(", ")+"};");
      emit.push("const "+names.state_ty(id)+" = @TypeOf("+names.state(id)+");");
      emit.push("_ = .{"+names.state(id) + ", " + names.state_ty(id)+"};");
      args_tmp = null;
    }else if(source.readIf("%}")) {
      if(state !== "fn_or_root") source.error("bad state");
      emit.push("}");
      assert(ids.pop() != null);
    // %| a b c %| to pass args to %[ %] ?
    }else if(source.readIf("%[")) {
      const parent_id = ids[ids.length - 1];
      if(parent_id == null) source.error("child block must be inside capturable function");
      const id = gid++;
      id_srclocs.set(id, source.srcloc);
      ids.push(id);
      emit.push("ui.Component{");
      emit.push(".data = @intFromPtr(&"+names.state(parent_id)+"),",);
      emit.push(".method = &struct{fn "+names.fn(id)+"( "+name("state_raw", id)+": usize ) void {");
      emit.push("const "+names.state_ty(id)+" = "+names.state_ty(parent_id)+";");
      emit.push("const "+names.state(id)+" = @as(*const "+names.state_ty(id)+", @ptrFromInt("+name("state_raw", id)+")).*;");
      emit.push("_ = .{"+names.state(id)+"};");
    }else if(source.readIf("%]")) {
      const sid = ids.pop();
      if(sid == null) source.error("ids empty");
      emit.push("}}."+names.fn(sid)+",",);
      emit.push("}",);
    }else if(source.readIf("%%")) {
      emit.push("%");
    }else{
      source.error("percent nothing");
    }
  }

  if(ids.length !== 0) {
    for(const id of ids) {
      const srcloc = id_srclocs.get(id) ?? null;
      source.error("missing close bracket for this open bracket", srcloc);
    }
  }
  if(state !== "fn_or_root") {
    source.error("bad state: "+state);
  }
}

function indent(level: number): string {
  return "  ".repeat(level);
}
type Stats = {
  files_processed: number,
};
async function compileObject(dirname: string, filename_unprefixed: string, indent_level: number, stats: Stats, beforeprint_parent: () => void): Promise<void> {
  const filename = dirname + "/" + filename_unprefixed;
  const file_stat = statSync(filename);
  if(filename_unprefixed.startsWith(".")) return;
  if(file_stat.isDirectory()) {
    let written = false;
    const beforeuse = () => {
      if(written) return;
      written = true;
      beforeprint_parent();
      process.stderr.write(indent(indent_level) + filename_unprefixed + "/\n");
    };
    await compileDirRecursive(filename, indent_level, stats, beforeuse);
    return;
  }
  if(!filename_unprefixed.endsWith(".zix")) return;

  beforeprint_parent();
  process.stderr.write(indent(indent_level) + filename_unprefixed + "\n");

  const out_filename = filename + ".zig";
  const content: string = await Bun.file(filename).text();
  try{
    let out: string[] = [];
    compileZix(new Tokenizer(content), out);
    const compiled = out.join("");
    await Bun.write(out_filename, compiled);
  }catch(e) {
    prettyDisplayError(filename, e);
  }

  stats.files_processed += 1;
}
async function compileDirRecursive(dirname: string, indent_level: number, stats: Stats, beforeprint_parent: () => void): Promise<void> {
  const dircont = readdirSync(dirname);
  for(const filename_unprefixed of dircont) {
    await compileObject(dirname, filename_unprefixed, indent_level + 1, stats, beforeprint_parent);
  }
}

const args = Bun.argv.slice(2);
for(const arg of args) {
  if(arg.startsWith("-")) {
    console.error("unsupported flag: "+arg);
    process.stderr.write("usage: zix_compiler [files/directories...]\n");
    process.exit(1);
  }
  const stats: Stats = {
    files_processed: 0,
  };
  const time_start = Date.now();
  const split = path.parse(arg);
  await compileObject(split.dir || ".", split.base, 0, stats, () => {});
  const time_end = Date.now();
  const ms_fmt = Intl.DurationFormat != null ? new Intl.DurationFormat(undefined, {style: "narrow"}).format({
    milliseconds: time_end - time_start,
  }) : ((time_end - time_start) / 1000).toFixed(2) + "s";
  console.log("" + stats.files_processed.toLocaleString() + " files processed in " + ms_fmt);
}

// prettyErrorHandle("a.zix", () => {
//   let out: string[] = [];
//   compileZix(new Tokenizer(`
//     fn Button%( %.item_one: []const u8, %.item_two: usize %) void %{
//       VStack(%[
//         std.log.info("value is: {d}, str: \"{s}\"", .{%.item_two, %.item_one});
//       %]);
//     %}
//   `), out);
//   console.log(out.join(""));
// });
