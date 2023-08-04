// https://github.com/pfgithub/customvariants/blob/738f9712e8c4fcab81a25b9eccefadf96d2bb1ae/src/util.ts#L2C36-L2C36
// |- from: https://github.com/pfgithub/qxc/blob/132a414b78f802d0d6dad8aa3309250c2faff27d/src/s2.ts#L2162
// |- from: https://github.com/pfgithub/scpl-cli/blob/e013a0972cf52580592baeee0c5b1c0282551a7b/bin/scpl.ts#L56
export function displayErrorLocation(fylnm: string, inbytes: Uint8Array, e: PositionedError) {
    const blue = "\x1b[34m";
    const yellow = "\x1b[33m";
    const red = "\x1b[91m";
    const inverse = "\x1b[7m";
    const hidden = "\x1b[8m";
    const reset = "\x1b(B\x1b[m";

    const emsg = e.toString();

    if(e.srcloc < 0) {
        console.log(`${blue}${fylnm}${reset} - [no location/${e.srcloc}] ${red}${emsg}${reset}`);
        return;
    }

    const pos_rev = e.srcloc;

    // find lyn/col::
    let lyn = 1; // lyn/col are one-indexed
    let col = 1;
    let lyn_start: Uint8Array = inbytes;
    for(let i = 0; i < pos_rev; i++) {
        if(inbytes[i] === 0x0A) { // newline
            lyn += 1;
            col = 1;
            lyn_start = inbytes.subarray(i + 1);
        }else{
            col += 1;
        }
    }
    // should col count
    // - utf-8 bytes
    // - utf-16 chars
    // or unicode codepoints
    // ?

    let lyn_txt: Uint8Array = lyn_start;
    for(let i = 0; i < lyn_start.length; i++) {
        if(lyn_start[i] === 0x0A) {
            lyn_txt = lyn_start.subarray(0, i);
            break;
        }
    }

    // consider syn hl for the printed line
    const blanklyn = " ".repeat(("" + lyn).length);
    const error_line = new TextDecoder().decode(lyn_txt);
    const before_error_pos = new TextDecoder().decode(lyn_txt.subarray(0, col - 1));
    console.log("");
    // consider printing more lines before this
    console.log(`${inverse}${lyn}${reset} ${error_line}`);
    console.log(`${inverse}${blanklyn}${reset} ${hidden}${before_error_pos}${reset}${red}^${reset}`);
    console.log(`${blue}${fylnm}${reset}:${yellow}${lyn}${reset}:${yellow}${col}${reset} - ${red}${emsg}${reset}`);
    console.log("");
}

export function prettyErrorHandle<T>(flnme: string, v: () => T): T {
    try {
        return v();
    }catch(e) {
        if(e instanceof PositionedError) {
            displayErrorLocation(flnme, e.srctxt, e);
            process.exit(1);
            // throw e;
        }else{
            throw e;
        }
    }
}

export function assertNever(v: never): never {
    console.log("not never", v);
    throw new Error("not never");
}

export const start_pos = Symbol("start_pos");
export const end_pos = Symbol("end_pos");

export class PositionedError extends Error {
    constructor(public name: string, msg: string, public srcloc: number, public srctxt: Uint8Array) {
        super(msg);
        this.name = name;
    }
    toString() {
        return "[" + this.name + "] " + this.message;
    }
}
