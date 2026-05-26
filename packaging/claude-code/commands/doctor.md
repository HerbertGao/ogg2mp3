---
description: 自检 ogg2mp3 转换环境是否就绪
argument-hint: ""
allowed-tools: Bash(ogg2mp3:*)
---

跑 `ogg2mp3 doctor --json` 拿到 JSON 报告。

用一段简洁中文向用户汇报：

- `ok` —— **核心结论**。true = 所有依赖就绪可以转换；false = 有问题
- `binary_version` —— 当前 ogg2mp3 版本（strict semver / CalVer-style 格式 `YYYY.M.0`，例如 `2026.5.0`）
- `checks[]` —— 8 个依赖工具的状态

如果 `ok: false`：列出所有 `found: false` 的工具，**把每个 `install_hint` 字段原样展示给用户**让他自己跑安装命令。明确告诉用户："修复后再跑 `/ogg2mp3:doctor` 重新检查。"

如果 `ok: true`：用一行简短确认（"环境就绪，可以开始转换"）即可，不要把全部 8 个 ok 状态都列出来——啰嗦无信息。
