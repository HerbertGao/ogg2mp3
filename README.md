# oggh2mp3

QQ音乐Mac版 ogg/oggh 格式音频文件带专辑封面转 mp3格式脚本

ogg/oggh 格式的音频文件为vorbis格式，专辑封面是icns格式的10张图片作为图标，并没有在音频文件的流或metadata里存储。

## 新功能：元数据提取和保留

脚本现在支持从原始OGG文件中提取元数据（标题、专辑、歌手、年份、流派等）并将其写入转换后的MP3文件。

脚本工作流程：

1. 从 ogg/oggh 文件中提取音频元数据（标题、专辑、歌手等）
2. 从 ogg/oggh 文件中提取icns图标资源
3. 将icns转换为png图片（自动选择最佳分辨率）
4. 使用ffmpeg将音频转换为mp3格式，同时写入元数据
5. 将封面嵌入mp3文件生成最终结果

## Features

- **元数据提取和保留**：自动提取OGG文件中的标题、专辑、歌手、年份、流派等元数据
- **智能元数据映射**：支持多种元数据字段格式的自动映射
- 自动依赖检查和错误处理
- 智能分辨率选择（优先512x512，依次降级）
- 详细的转换进度提示
- 自动清理临时文件
- 完整的错误处理机制

## Dependencies

- Command Line Tools
  - `xcode-select --install`
- [relikd/icnsutil](https://github.com/relikd/icnsutil)
  - `pip3 install icnsutil`
- ffmpeg
  - `brew install ffmpeg`
- jq (用于元数据JSON解析)
  - `brew install jq`

## Usage

```shell
chmod +x oggh2mp3.sh
./oggh2mp3.sh [INPUT.oggh]
```

脚本会生成两个文件：

- `[filename].mp3` - 无封面版本
- `[filename]_with_cover.mp3` - 带封面版本

转换过程中会显示提取到的元数据信息，转换完成后可选择删除无封面版本。
