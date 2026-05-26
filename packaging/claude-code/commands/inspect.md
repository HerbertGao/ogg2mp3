---
description: 只读查看 .ogg/.oggh 文件的元数据和封面信息（不转换）
argument-hint: "<file>"
allowed-tools: Bash(ogg2mp3:*)
---

用户参数：`$ARGUMENTS`

把第一个参数当输入文件路径，跑：
```
ogg2mp3 inspect "<file>" --json
```

把 JSON 结果用中文友好地呈现给用户：

- 文件路径 + 编码（`codec`）+ 时长（`duration_sec` 秒转分:秒）+ 比特率（`bitrate` bps 转 kbps）
- 元数据：把 `metadata` 对象里**有意义的字段**（TITLE / ARTIST / ALBUM / DATE / GENRE / TRACK 之类）列出来。**忽略** `end` / `endserial` / `endgran` 这些 Vorbis 内部字段（无用户价值）
- 封面：`cover.present` true 则显示尺寸 KB；false 明确说"无封面（Resource Fork 里没有 ICNS 资源——可能不是 QQ 音乐下载的）"

不要建议下一步操作（转不转、要不要补封面），除非用户问。这个命令的定位是**只读查询**。

如果用户没提供文件（`$ARGUMENTS` 为空），告诉用户用法：`/ogg2mp3:inspect <file>`，不要瞎调。
