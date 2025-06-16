///|
fn main {
  @async.start(fn() { cat(@env.args()[1:]) }) catch {
    e => println("Error running cat: \{e}")
  }
}

///|
async fn cat(files : ArrayView[String]) -> Unit raise {
  if files is [] {
    // read from stdin only once
    read_streaming(@async.stdin)
  } else {
    for file in files {
      if file is "-" {
        // read from stdin
        read_streaming(@async.stdin)
        continue
      } else {
        read_all(@async.path(file))
      }
    }
  }
}

///|
async fn[T : @async.Readable] read_all(input : T) -> Unit raise {
  @async.stdout.write_text(input.read_text(encoding=UTF8), encoding=UTF8)
}

///|
async fn[T : @async.Readable] read_streaming(input : T) -> Unit raise {
  let decoder = @encoding.decoder(UTF8)
  let string = []
  let stream = input.read()
  stream.each(fn(bytes) {
    let str = decoder.decode(bytes, stream=true)
    if str.find("\n") is Some(index) {
      for i = 0; i < string.length(); i = i + 1 {
        @async.stdout.write_text(string[i], encoding=UTF8)
      }
      @async.stdout.write_text(str.charcodes(end=index + 1), encoding=UTF8)
      string.clear()
      string.push(str.charcodes(start=index + 1))
    }
  })
}
