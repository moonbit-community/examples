///|
priv struct Option {
  mut recurse : Bool
  mut level : UInt?
} derive(Show)

///|
impl @clap.Value for Option with add_value(self, name, value, positional) {
  if name is "level" && not(positional) {
    try {
      self.level = Some(@strconv.parse_uint(value))
    } catch {
      e =>
        raise @clap.InvalidArgumentValue(
          "\"--level\" should be an integer. Got \{e}",
        )
    }
  }
}

///|
impl @clap.Value for Option with set_flag(self, name, value) {
  if name is "recurse" {
    self.recurse = value
  }
}

///|
fn main {
  @async.start(fn() {
    let opt = { recurse: false, level: None }
    let parser = @clap.Parser::new(prog="ls", args={
      "recurse": @clap.Arg::flag(short='R', help="recurse into directories"),
      "level": @clap.Arg::named(
        short='L',
        help="limit the depth of recursion",
        nargs=@clap.Nargs::AtMost(1),
      ),
    })
    let help = parser.parse(opt, @env.args()[1:]) catch {
      InvalidArgumentValue(e) => {
        @async.stderr.write_text("Error: \{e}\n", encoding=UTF8)
        return
      }
      e => {
        @async.stderr.write_text("Error: \{e}\n", encoding=UTF8)
        return
      }
    }
    if help is Some(help) {
      @async.stdout.write_text(help, encoding=UTF8)
      return
    }
    let dir = ls(
      path?=@env.current_dir(),
      depth?=if opt.recurse { opt.level } else { Some(0) },
    )
    dir.display()
  }) catch {
    e => println("Error running cat: \{e}")
  }
}

///|
enum File {
  File(&@async.ToPath)
  Directory(&@async.ToPath, Array[File])
}

///|
async fn ls(path? : String, depth? : UInt) -> File raise {
  let file = if path is Some(path) {
    File::from_path(path, depth?)
  } else {
    File::from_path(@async.cwd(), depth?)
  }
  file
}

///|
async fn File::from_path(path : &@async.ToPath, depth? : UInt) -> File raise {
  if path.is_dir() {
    let entries = []
    if depth is Some(0) {
      // When depth is 0, still list direct entries but don't recurse
      path
      .iter()
      .each(fn(entry) {
        if entry.is_dir() {
          entries.push(Directory(entry, []))
        } else {
          entries.push(File(entry))
        }
      })
    } else {
      path
      .iter()
      .each(fn(entry) {
        entries.push(
          File::from_path(entry, depth?=depth.map(UInt::op_sub(_, 1))),
        )
      })
    }
    Directory(path, entries)
  } else {
    File(path)
  }
}

///|
async fn File::display(self : File) -> Unit raise {
  match self {
    File(path) => print("\{path.name()}\n")
    Directory(root, entries) => {
      let chalk = @chalk.chalk().color(Blue)
      let queue = @queue.new()
      for entry in entries {
        if entry is Directory(path, _) {
          print(chalk.render("\{path.name()} "))
          queue.push(entry)
        } else if entry is File(path) {
          print("\{path.name()} ")
        }
      }
      print("\n")
      while queue.pop() is Some(f) {
        if f is File(path) {
          print(path.name())
        } else if f is Directory(p, entries) {
          // Only show subdirectory contents if they have entries (i.e., depth > 0)
          if entries.length() > 0 {
            print("\n./\{p.relative_to(root)}:\n")
            for entry in entries {
              if entry is Directory(path, _) {
                print(chalk.render("\{path.name()} "))
                queue.push(entry)
              } else if entry is File(path) {
                print("\{path.name()} ")
              }
            }
            print("\n")
          }
        }
      }
    }
  }
}

///|
async fn print(s : String) -> Unit raise {
  @async.stdout.write_text(s, encoding=UTF8)
}
