# 打包开发日志

## 2026-04-19 — 工作目录传递修复 + 资源管理器右键菜单

### 问题描述

安装包安装完成后，通过桌面快捷方式或开始菜单启动 Claude Code Best，工作目录始终是安装目录（`%LOCALAPPDATA%\ClaudeCodeBest\`），而非用户当前所在的项目目录。原生 CLI 的使用方式（在项目目录下打开终端 → 执行 `claude`）无法复现。

**根因**：`launcher.ps1` 使用 `Start-Process` 打开新终端窗口时未传递 `-WorkingDirectory`，新进程与调用者的 CWD 完全断开。

---

### 修改清单

#### `packaging/launcher.ps1`

- 在构建参数列表之前检查 `$PassArgs` 是否已含 `--cwd`。
  - 若**无** `--cwd`（终端启动场景）：自动捕获 `$PWD.Path` 并在参数头部注入 `--cwd <当前目录>`。
  - 若**有** `--cwd`（资源管理器右键菜单场景，Explorer 已通过 `%1`/`%V` 传入正确路径）：保持原样，不再重复注入。
- 最后一个直接启动回退路径（`Start-Process $CoreExe`）改用 `$quoted` 数组，确保 `--cwd` 同样被传递。

#### `src/entrypoints/cli.tsx`

在 `main()` 最顶部、Commander 解析和任何模块加载之前，新增对 `--cwd <path>` 的早期处理：

1. 调用 `process.chdir(path)` 切换进程工作目录。
2. 从 `process.argv` 和本地 `args` 数组中删除 `--cwd` 及其值，防止 Commander 报"未知选项"错误。

这样 `getCwd()`、`bootstrap/state.ts` 的 `originalCwd`/`projectRoot`/`cwd` 均以正确目录初始化，`/init`、文件读写、git 操作全部正常。

#### `packaging/installer.iss`

新增安装选项 `contextmenu`（System integration 分组，默认勾选）：

| 注册表键 | 用途 |
|---|---|
| `HKCU\Software\Classes\Directory\shell\ClaudeCodeBest` | 右键点击**文件夹本身**时显示菜单项，传递 `%1` 作为 `--cwd` |
| `HKCU\Software\Classes\Directory\Background\shell\ClaudeCodeBest` | 在文件夹**内部空白处**右键时显示菜单项，传递 `%V` 作为 `--cwd` |

两个键均标记 `Flags: uninsdeletekey`，卸载时自动清理。

---

### 支持的三种启动方式

| 方式 | 操作 | CWD 来源 |
|---|---|---|
| 终端命令 | 在任意目录 `cd` 后执行 `ClaudeCode` | `$PWD.Path`（launcher 注入） |
| 资源管理器右键 | 文件夹上或文件夹内右键 → *Open Claude Code Best here* | Explorer 的 `%1` / `%V` |
| 命令行显式指定 | `ClaudeCode --cwd "D:\proj"` | 用户参数（launcher 不覆盖） |

---

### `packaging/build-exe.ps1` 顺带修复的脚本 Bug

| 行 | 问题 | 修复 |
|---|---|---|
| 43 | 引用了未定义变量 `$PkgTarget`（pkg 时代遗留） | 删除该行 |
| 127-129 | `@()` 内用逗号分隔 `Join-Path` 调用，PowerShell 解析成嵌套数组导致 `ParameterBindingException` | 每个元素加括号 `(Join-Path ...)` |
| 213 | 使用 `?.Source` 空条件运算符，PowerShell 5.x 不支持 | 改为显式 `if ($cmd) { $x = $cmd.Source }` |

---

### 重新部署

```powershell
# 只需重编译 launcher + 重打安装包，claude-core.exe 无需重新编译
.\packaging\build-exe.ps1 -SkipBuild
```
