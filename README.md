# oggh2mp3

QQ音乐Mac版 oggh格式音频文件带专辑封面转 mp3格式脚本

oggh格式的音频文件为vorbis格式，专辑封面是icns格式的10张图片作为图标，并没有在音频文件的流或metadata里存储。

脚本工作流程：

1. 从oggh文件中提取icns图标资源
2. 将icns转换为png图片（自动选择最佳分辨率）
3. 使用ffmpeg将音频转换为mp3格式
4. 将封面嵌入mp3文件生成最终结果

## Features

- 自动依赖检查和错误处理
- 智能分辨率选择（优先512x512，依次降级）
- 详细的转换进度提示
- 可选择是否保留无封面版本
- 自动清理临时文件

## Dependencies

- Command Line Tools
  - `xcode-select --install`
- [relikd/icnsutil](https://github.com/relikd/icnsutil)
  - `pip3 install icnsutil`
- ffmpeg
  - `brew install ffmpeg`

## Usage

```shell
chmod +x oggh2mp3.sh
./oggh2mp3.sh [INPUT.oggh]
```

脚本会生成两个文件：

- `[filename].mp3` - 无封面版本
- `[filename]_with_cover.mp3` - 带封面版本

转换完成后可选择删除无封面版本。
