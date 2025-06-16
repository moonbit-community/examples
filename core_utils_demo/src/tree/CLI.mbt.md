---
moonbit:
  deps:
    tonyfettes/uv: 0.7.4
    TheWaWaR/clap: 0.2.3
  backend: native
---

# 使用 MoonBit 开发 tree 命令行工具

本文将介绍如何使用 MoonBit 语言开发一个类似 Unix `tree`
命令的命令行工具。我们将使用 `uv.mbt`
库进行文件系统操作，并展示如何构建一个功能完整的 CLI 应用程序。

## 项目结构

在开始之前，让我们了解一下项目的基本结构：

```
top/
├── moon.mod.json
└── src/
    ├── moon.pkg.json
    └── top.mbt          # 主程序入口
```

## 依赖配置

我们需要在项目中配置以下依赖：

- `tonyfettes/uv: 0.7.4` - 提供异步 I/O 和文件系统操作
- `TheWaWaR/clap: 0.2.3` - 命令行参数解析

在 `moon.mod.json` 中添加这些依赖：

```json
{
  // ...
  "deps": {
    "tonyfettes/uv": "0.7.4",
    "TheWaWaR/clap": "0.2.3"
  }
}
```

## tree 命令的核心功能

`tree`
命令的主要功能是递归地显示目录结构，以树状格式展示文件和文件夹的层次关系。

### 基本实现思路

1. **解析命令行参数** - 确定要显示的目录路径和选项
2. **递归遍历目录** - 使用文件系统 API 读取目录内容
3. **格式化输出** - 使用树状字符（如 `├──`、`└──`）美化显示

## tree 命令的实现

基于以上分析，我们可以开始实现 tree 命令：

### 1. 配置模块

在 `moon.pkg.json` 中配置模块依赖：

```json
{
  "import": [
    "tonyfettes/uv/async",
    "tonyfettes/encoding",
    "TheWaWaR/clap"
  ],
  "is-main": true
}
```

定义其为可执行程序入口并添加依赖。

### 2. 核心数据结构

定义用于表示目录树的数据结构：

```moonbit
// 树节点结构
struct TreeNode {
  name : String
  children : Array[TreeNode]
}

// 配置选项
struct TreeOptions {
  mut path : String // 根路径
  mut show_hidden : Bool // 是否显示隐藏文件
  mut max_depth : UInt? // 最大深度
  mut dirs_only : Bool // 仅显示目录
} derive(Show)

impl Default for TreeOptions with default() {
  { path: ".", show_hidden: false, max_depth: None, dirs_only: false }
}
```

### 3. 解析命令行参数

我们利用 `clap` 这个包来从命令行构造 `TreeOptions`。为此，我们需要给
`TreeOptions` 实现 `@clap.Value`
来告诉它应当如何将解析的参数变为我们定义的选项。其中，`show_hidden` 与
`dirs_only` 为开关标识，而 `max_depth` 则为具体的值。因此分别用两个方法来实现：

```moonbit
impl @clap.Value for TreeOptions with add_value(self, name, value, positional) {
  if name is "level" && not(positional) {
    try {
      self.max_depth = Some(@strconv.parse_uint(value))
    } catch {
      e =>
        raise @clap.InvalidArgumentValue(
          "\"--level\" should be an integer. Got \{e}",
        )
    }
  }
  if name is "path" && positional {
    self.path = value
  }
}

impl @clap.Value for TreeOptions with set_flag(self, name, value) {
  if name is "all" {
    self.show_hidden = value
  } else if name is "only-dirs" {
    self.dirs_only = value
  }
}
```

之后，我们需要定义一个解析器，在其中提供更详细的配置，包括每个指令的帮助信息：

```moonbit
let parser : @clap.Parser = @clap.Parser::new(prog="tree", args={
  "all": @clap.Arg::flag(short='A', help="show hidden files"),
  "only-dirs": @clap.Arg::flag(short='D', help="list only directories"),
  "level": @clap.Arg::named(
    short='L',
    help="limit the depth of recursion",
    nargs=@clap.Nargs::AtMost(1),
  ),
  "path": @clap.Arg::positional(
    nargs=@clap.Nargs::AtMost(1),
    help="directory to visit. Default to .",
  ),
})
```

我们可以简单测试一下：

```moonbit
test "help" {
  // 默认值
  let option = TreeOptions::default()
  guard parser.parse(option, ["-h"]) is Some(help_message)
  inspect(
    help_message,
    content=
      #|Usage: tree [OPTIONS] [PATH]
      #|
      #|Arguments:
      #|  [PATH]  directory to visit. Default to .
      #|
      #|Options:
      #|  -A, --all            show hidden files
      #|  -D, --only-dirs      list only directories
      #|  -L, --level <LEVEL>  limit the depth of recursion
      #|  -h, --help           Print help
      #|
    ,
  )
}

test "max depth" {
  // 默认值
  let option = TreeOptions::default()
  guard parser.parse(option, ["-L", "10"]) is None
  inspect(
    option,
    content=
      #|{path: ".", show_hidden: false, max_depth: Some(10), dirs_only: false}
    ,
  )
}

test "path" {
  let option = TreeOptions::default()
  guard parser.parse(option, ["src/cat"]) is None
  inspect(
    option,
    content=
      #|{path: "src/cat", show_hidden: false, max_depth: None, dirs_only: false}
    ,
  )
}
```

### 4. 递归遍历目录

目录遍历逻辑为：

1. **递归读取目录**：从指定路径开始，递归遍历所有子目录
2. **过滤逻辑**：根据配置选项过滤隐藏文件、限制深度等
3. **数据结构构建**：将文件系统结构转换为树形数据结构

为此，我们需要使用 `@async`
中提供的各类函数，并定义递归函数进行处理。需要注意的是，需要对根结点的名称进行特殊处理。

```moonbit
async fn TreeNode::new(option : TreeOptions) -> TreeNode! {
  let path = option.path as &@async.ToPath
  guard path.is_dir() else { fail!("error opening dir \{path}") }
  async fn aux!(p : &@async.ToPath, depth) {
    if option.max_depth is Some(max_depth) && max_depth == depth {
      TreeNode::{
        name: if depth == 0 {
          option.path
        } else {
          path.name()
        },
        children: [],
      }
    } else {
      let children = []
      p
      .iter()
      .each(fn(entry) {
        guard option.show_hidden || not(entry.name().has_prefix(".")) else {
          return
        }
        if entry.is_dir() {
          children.push(aux(entry, depth + 1))
        } else {
          guard not(option.dirs_only) else { return }
          children.push(TreeNode::{ name: entry.name(), children: [] })
        }
      })
      TreeNode::{
        name: if depth == 0 {
          option.path
        } else {
          path.name()
        },
        children,
      }
    }
  }

  aux(option.path, 0)
}
```

### 5. 格式化输出

我们定义一个输出对象，方便调试:

```moonbit
trait Output {
  async print(Self, @string.View) -> Unit!
}

/// 用于测试环境
impl Output for StringBuilder with print(self, text) {
  self.write_string(text.to_string())
}

/// 实际执行环境
impl Output for @async.File with print(self, text) {
  self.write_text(text.to_string(), encoding=UTF8)
}
```

使用树状字符美化输出，常用的字符包括：

- `├──` 用于中间项目
- `└──` 用于最后一个项目
- `│` 用于连接线
- `` 用于空白缩进

```moonbit
// 用于根节点的打印函数
async fn[O : Output] TreeNode::print_root(node : TreeNode, output : O) -> Unit! {
  output.print("\{node.name}\n")
  for i = 0; i < node.children.length(); i = i + 1 {
    let child = node.children[i]
    let is_last_child = i == node.children.length() - 1
    child.print(output, "", is_last_child)
  }
}

// 用于子节点的打印函数
async fn[O : Output] TreeNode::print(
  node : TreeNode,
  output : O,
  prefix : String,
  is_last : Bool
) -> Unit! {
  let connector = if is_last { "└── " } else { "├── " }
  output.print("\{prefix}\{connector}\{node.name}\n")
  let new_prefix = prefix + (if is_last { "    " } else { "│   " })
  for i = 0; i < node.children.length(); i = i + 1 {
    let child = node.children[i]
    let is_last_child = i == node.children.length() - 1
    child.print(output, new_prefix, is_last_child)
  }
}
```

这个函数递归地打印整个树结构，使用不同的前缀字符来表示层级关系。

为此，我们可以进行一些测试：

```moonbit
test "single root node" {
  @async.start(fn() {
    let builder = StringBuilder::new()
    let tree = TreeNode::{ name: "src", children: [] }
    tree.print_root(builder)
    inspect(
      builder.to_string(),
      content=
        #|src
        #|
      ,
    )
  })
}

test "tree with children" {
  @async.start(fn() {
    let builder = StringBuilder::new()
    let child1 = TreeNode::{ name: "file1.txt", children: [] }
    let child2 = TreeNode::{ name: "file2.txt", children: [] }
    let tree = TreeNode::{ name: "src", children: [child1, child2] }
    tree.print_root(builder)
    inspect(
      builder.to_string(),
      content=
        #|src
        #|├── file1.txt
        #|└── file2.txt
        #|
      ,
    )
  })
}
```

## 编译和运行

程序的入口应当定义为：

```moonbit x
fn main {
  try
  @async.start(fn() {
    let option = TreeOptions::default()
    parser.parse(option, @env.args[1:]) |> ignore
    let tree_node = TreeNode::new(option)
    tree_node.print_root(@async.stdout)
  })
  catch {
    e => println("Error: \{e}")
  }
}
```

使用 MoonBit 的构建系统：

```bash
# 编译项目
moon build

# 使用 moon run，并传递参数
moon run src -- -h
```

```moonbit
test {
  @async.start(fn() {
    let option = TreeOptions::default()
    parser.parse(option, ["./src/tree"]) |> ignore
    let tree_node = TreeNode::new(option)
    let output = StringBuilder::new()
    tree_node.print_root(output)
    inspect(
      output.to_string(),
      content=
        #|./src/tree
        #|├── CLI.mbt.md
        #|└── moon.pkg.json
        #|
      ,
    )
  })
}
```

## 总结

通过本文，我们学习了：

1. 如何使用 MoonBit 的异步 I/O 系统
2. 如何处理命令行参数和错误
3. 如何实现递归的文件系统遍历
4. 如何格式化输出树状结构

这个 tree 命令的实现展示了 MoonBit 在系统编程和 CLI 工具开发方面的能力。通过结合
`uv.mbt` 库的强大功能，我们可以构建高效、可靠的命令行应用程序。

### 扩展功能

你可以进一步扩展这个 tree 命令：

- 添加颜色输出支持
- 实现文件大小显示
- 支持更多命令行选项，以及遵守 .gitignore 的规则
- 支持多种输出格式（JSON、XML 等）
