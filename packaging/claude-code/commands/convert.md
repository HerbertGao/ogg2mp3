---
description: 转换单个 .ogg/.oggh 文件为 .mp3（带封面和元数据）
argument-hint: "<file> [--overwrite] [--no-cover] [--no-metadata]"
allowed-tools: Bash(ogg2mp3:*)
---

用户参数：`$ARGUMENTS`

把第一个参数当作输入文件路径，其余作为额外 flag 透传。**必须始终加上 `--yes --json`**（slash command 是非交互上下文）。

调用形式：
```
ogg2mp3 convert "<file>" --yes --json [...passthrough flags]
```

解析 JSON 结果：

- `ok: true` —— 转换成功。一句话告诉用户：输出路径（`output`）、是否带封面（`cover_embedded`）、嵌入了几个元数据字段（`metadata_fields`）
- `cover_embedded: false` —— 不是错误。**主动提示用户**："这个文件可能不是 QQ 音乐下载的（没有 ICNS 封面资源），MP3 已生成但无专辑封面。"
- 退出码非 0 —— 转换失败。从 stderr 读 `ffmpeg:` 开头的行抓真因，告诉用户哪一步坏了

如果用户没提供文件路径（`$ARGUMENTS` 为空），告诉用户用法：`/ogg2mp3:convert <file>`，不要瞎调命令。

如果用户没明确要求覆盖，但目标 .mp3 已存在导致 `exit 1` "output exists"，**问用户**是否要加 `--overwrite` 重跑，不要自作主张覆盖。
