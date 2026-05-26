# ogg2mp3

QQ 音乐 Mac 版 `.ogg` / `.oggh` 音频转 `.mp3` 脚本，自动保留专辑封面和元数据。

> QQ 音乐默认下载格式后缀已从 `.oggh` 改为 `.ogg`，本脚本两者都支持。
> 文件本质是 Vorbis 音频 + macOS Resource Fork 里的 ICNS 专辑封面（10 张图标），封面没有写在音频流或 metadata 里，必须用 `derez` 单独提出来。

## 工作流程

1. 用 `ffprobe` 从 OGG 流和 format 里抽元数据（title / album / artist / date / genre / track 等）
2. 用 `derez` 把 Resource Fork 里的 ICNS 提出来，`icnsutil` 拆成多分辨率 PNG，选最高的（512x512 优先，依次降级）
3. 一次性 `ffmpeg` 调用同时完成：音频转码 MP3、嵌入元数据、嵌入封面（id3v2.3）

## Commands

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
./ogg2mp3.sh convert song.ogg                       # 输出 song.mp3
./ogg2mp3.sh convert song.ogg -o /tmp/out.mp3       # 自定义输出
./ogg2mp3.sh convert song.ogg --no-cover            # 跳过封面
./ogg2mp3.sh convert song.ogg --overwrite --yes     # 非交互覆盖
./ogg2mp3.sh convert song.ogg --json                # JSON 结果
```

### batch

```shell
./ogg2mp3.sh batch ~/Music/QQMusic                          # 仅顶层
./ogg2mp3.sh batch ~/Music/QQMusic -r --skip-existing       # 递归 + 跳过已转换
./ogg2mp3.sh batch ~/Music/QQMusic -r --dry-run             # 只列出会做什么
./ogg2mp3.sh batch ~/Music/QQMusic -r --overwrite --json    # NDJSON 输出供 Agent 消费
```

`--skip-existing` 与 `--overwrite` 互斥；两者都不加时已存在的输出会被记为 FAIL（保护性默认）。

### inspect

```shell
./ogg2mp3.sh inspect song.ogg          # 人类可读
./ogg2mp3.sh inspect song.ogg --json   # JSON：file / codec / duration / bitrate / metadata / cover
```

### doctor

```shell
./ogg2mp3.sh doctor          # 检查 ffmpeg/ffprobe/derez/icnsutil/jq/xxd 等是否就绪
./ogg2mp3.sh doctor --json   # 机器可读
```

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
| 3 | 依赖缺失 |
| 130 | 用户中断（Ctrl-C） |

## Dependencies

- macOS 命令行工具（提供 `derez`）：`xcode-select --install`
- [icnsutil](https://github.com/relikd/icnsutil)：`pipx install icnsutil`（如果没有 pipx：`brew install pipx`。新 macOS 上 PEP 668 拦截裸 `pip3 install`，所以走 pipx）
- ffmpeg / ffprobe：`brew install ffmpeg`
- jq：`brew install jq`

先跑 `./ogg2mp3.sh doctor` 检查环境。

## Install

```shell
chmod +x ogg2mp3.sh
./ogg2mp3.sh doctor
```
