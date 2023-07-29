
class Tokenizer {
  source: string;


}

function compileZix(source: Tokenizer, emit: string[]) {
  let state = "";
  while(true) {
    emit.push(source.readUntil("%"));
    if(source.readIf("%(")) {
      state = "args";
      emit.push("(");
    }else if(source.readIf("%)")) {
      state = "fn_body";
      emit.push(")");
    }else if(source.readIf("%.")) {

    }
  }
}
