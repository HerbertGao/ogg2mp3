# ogg2mp3

QQ 音乐 Mac 版 `.ogg` / `.oggh` 音频转 `.mp3` 脚本，自动保留专辑封面和元数据。**既是 CLI 工具，也是 Claude Code / Codex CLI 的 Plugin & Skill**——可以在终端直接调，也可以用自然语言驱动 AI Agent 完成转换。

> QQ 音乐默认下载格式后缀已从 `.oggh` 改为 `.ogg`，本脚本两者都支持。
> 文件本质是 Vorbis 音频 + macOS Resource Fork 里的 ICNS 专辑封面（10 张图标），封面没有写在音频流或 metadata 里，必须用 `derez` 单独提取出来。

## 工作流程

1. 用 `ffprobe` 从 OGG 流和 format 里抽元数据（title / album / artist / date / genre / track 等）
2. 用 `derez` 把 Resource Fork 里的 ICNS 提出来，`icnsutil` 拆成多分辨率 PNG，先用 `ffmpeg` 验证哪张是合法 PNG（icnsutil 会把 JP2K 之类 ICNS 子类型也写成 `.png`，要剔除），再选最高分辨率
3. 一次性 `ffmpeg` 调用同时完成：音频转码 MP3、嵌入元数据、嵌入封面（id3v2.3）

## 安装

```shell
git clone https://github.com/HerbertGao/ogg2mp3
cd ogg2mp3
bash scripts/install.sh   # 软链 ogg2mp3.sh → ~/.local/bin/ogg2mp3
ogg2mp3 doctor            # 自检依赖
```

`install.sh` 幂等可重跑，拒绝 root 运行，会检测 `~/.local/bin` 是不是已经在 PATH 里。

> 直接 `./ogg2mp3.sh <command>` 也能用，但 AI Agent 调用、跨目录使用都依赖 PATH 安装。建议跑一次 `install.sh`。

## CLI 用法

```text
ogg2mp3 <command> [args] [flags]
ogg2mp3                       # 交互菜单（无参运行）

  convert <input>             转换单个 .ogg/.oggh 文件
  batch <dir>                 批量转换目录
  inspect <input>             只读：dump 元数据 + 封面信息
  doctor                      依赖与环境自检
  help | version
```

### convert

```shell
ogg2mp3 convert song.ogg                       # 输出 song.mp3
ogg2mp3 convert song.ogg -o /tmp/out.mp3       # 自定义输出
ogg2mp3 convert song.ogg --no-cover            # 跳过封面
ogg2mp3 convert song.ogg --overwrite --yes     # 非交互覆盖
ogg2mp3 convert song.ogg --json                # JSON 结果
```

### batch

```shell
ogg2mp3 batch ~/Music/QQ音乐                          # 仅顶层
ogg2mp3 batch ~/Music/QQ音乐 -r --skip-existing       # 递归 + 跳过已转换
ogg2mp3 batch ~/Music/QQ音乐 -r --dry-run             # 只列出会做什么
ogg2mp3 batch ~/Music/QQ音乐 -r --overwrite --json    # NDJSON 输出供 Agent 消费
```

`--skip-existing` 与 `--overwrite` 互斥；两者都不加时已存在的输出会被记为 FAIL（保护性默认）。

### inspect

```shell
ogg2mp3 inspect song.ogg          # 人类可读
ogg2mp3 inspect song.ogg --json   # JSON：file / codec / duration / bitrate / metadata / cover
```

### doctor

```shell
ogg2mp3 doctor          # 检查 ffmpeg/ffprobe/derez/icnsutil/jq/xxd 等是否就绪
ogg2mp3 doctor --json   # 机器可读，含 binary_version 顶层字段
```

## AI Agent 用法（Claude Code / Codex CLI）

这个仓库本身就是 **Claude Code + Codex CLI 双 host 的 Plugin Marketplace**。装好以后，你可以在 host 里用自然语言驱动转换，不用记 flag。

### Claude Code

在 Claude Code 终端里：

```text
/plugin marketplace add /path/to/ogg2mp3
/plugin install ogg2mp3@ogg2mp3
```

然后就有了：

- **SKILL** —— Claude 会自动识别"把这个 QQ 音乐文件转成 MP3"「批量转换 QQ 音乐文件夹」这类意图，调对应子命令
- 4 个 slash command：`/ogg2mp3:doctor`、`/ogg2mp3:convert <file>`、`/ogg2mp3:batch <dir>`、`/ogg2mp3:inspect <file>`

### Codex CLI

类似流程，marketplace 地址同上路径（`.agents/plugins/marketplace.json` 自动被识别）。装好后 Codex 也能用自然语言驱动同款 4 个能力。

### Skill 设计要点

- **SOT 单一真相源**：`packaging/skill/ogg2mp3/SKILL.md` 是唯一被维护的 Skill 描述。`scripts/sync-skill.sh` 把它字节级同步到两个 host 的副本，避免漂移
- **Agent 行为约定**：SKILL.md 明确告诉 Agent 哪些能力**不可调用**（无参运行的交互菜单、不带 `--yes` 的写操作 —— 在非交互上下文会立即 exit 1）
- **JSON 契约固定**：每个子命令 `--json` 输出都有写死的 schema，doctor 顶层带 `binary_version` 让 Agent 校验最低版本（当前 `min_binary_version: 2026.5.0`）

## 输出契约

| 流 | 内容 |
|---|---|
| `stdout` | 数据：`convert` 输出最终路径一行；`batch` 每行 `OK\t<path>` / `FAIL\t<path>\t<reason>` / `SKIP\t<path>`；`--json` 模式输出结构化 JSON |
| `stderr` | 全部日志（进度、警告、错误） |

| 退出码 | 含义 |
|---|---|
| 0 | 成功 |
| 1 | 业务失败（转换失败 / batch 有任何失败项） |
| 2 | 参数错误 |
| 3 | 依赖缺失 / 以 root 身份运行（被 `require_unprivileged` 拒绝） |
| 130 | 用户中断（Ctrl-C） |

## 依赖

- macOS 命令行工具（提供 `derez`）：`xcode-select --install`
- [icnsutil](https://github.com/relikd/icnsutil)：`pipx install icnsutil`（如果没有 pipx：`brew install pipx`。新 macOS 上 PEP 668 拦截裸 `pip3 install`，所以走 pipx）
- ffmpeg / ffprobe：`brew install ffmpeg`
- jq：`brew install jq`

不知道缺啥就跑 `ogg2mp3 doctor`，缺什么会原样给出对应的 `install_hint`。

## 项目结构

```
ogg2mp3.sh                                    # 主 CLI
scripts/
├── install.sh                                # 软链到 ~/.local/bin
└── sync-skill.sh                             # SOT → 两个 host 副本
packaging/
├── skill/ogg2mp3/SKILL.md                    # SOT（唯一真相源）
├── claude-code/                              # Claude Code plugin
│   ├── .claude-plugin/plugin.json
│   ├── commands/{doctor,convert,batch,inspect}.md
│   └── skills/ogg2mp3/SKILL.md               # 副本，由 sync-skill.sh 维护
└── codex/                                    # Codex CLI plugin（schema 与 Claude 不同）
    ├── .codex-plugin/plugin.json
    └── skills/ogg2mp3/SKILL.md               # 副本
.claude-plugin/marketplace.json               # Claude Code marketplace 入口
.agents/plugins/marketplace.json              # Codex marketplace 入口
```

## 版本

CalVer，3 段格式（`年.月.补丁号`）—— 三段是 Codex plugin manifest 强制要求的 strict semver 兼容。当前 `2026.5.0`。

## License

MIT
