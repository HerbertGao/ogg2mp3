---
description: 批量把目录里的 .ogg/.oggh 转成 .mp3（默认递归 + 跳过已转换）
argument-hint: "<dir> [--overwrite] [--dry-run] [--no-cover]"
allowed-tools: Bash(ogg2mp3:*)
---

用户参数：`$ARGUMENTS`

第一个参数是目录路径。**默认策略**：递归 + 跳过已存在 + 非交互 + JSON：
```
ogg2mp3 batch "<dir>" -r --skip-existing --yes --json [...passthrough flags]
```

如果用户在 `$ARGUMENTS` 里显式传了 `--overwrite`、`--dry-run` 等，原样透传（注意 `--overwrite` 和 `--skip-existing` 互斥——透传 `--overwrite` 时去掉默认的 `--skip-existing`）。

输出是 NDJSON（每行一个对象）。汇总：

- 数 `ok: true && !skipped` 多少条（实际转换的）
- 数 `skipped: true` 多少条
- 数 `ok: false` 多少条；如果有，列出失败的 input 和 error
- 如果有任何 `cover_embedded: false`，单独提一句"X 个文件没成功嵌入封面（可能不是 QQ 音乐源）"

如果命令退出码 0：用一行总结成功结果，例："转换 12 个文件，跳过 3 个已存在，全部带封面。"
如果退出码 1：列出失败的文件，告诉用户具体哪几个出问题、可能原因。

如果用户没提供目录（`$ARGUMENTS` 为空），告诉用户用法：`/ogg2mp3:batch <dir>`，不要瞎调。

**不要主动 `--overwrite`**——即使用户说"重新转一下"，先问清楚是只补缺还是全量重转。
