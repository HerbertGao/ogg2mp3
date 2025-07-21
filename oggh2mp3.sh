#!/bin/bash

# 检查命令行参数
if [ $# -eq 0 ]; then
  echo "Please provide a file path as the argument."
  exit 1
fi

file="$1"

# 检查输入文件是否存在
if [[ ! -f "$file" ]]; then
    echo "Error: Input file '$file' not found."
    exit 1
fi

# 检查必要工具是否存在
check_dependencies() {
    local missing_tools=()
    
    for tool in ffmpeg derez icnsutil grep sed xxd; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo "Error: Missing required tools: ${missing_tools[*]}"
        echo "Please install the missing dependencies."
        exit 1
    fi
}

# 从oggh文件提取封面
extract_oggh_cover() {
    local input_file="$1"
    local tmp_dir="$2"
    local icns_file="$tmp_dir/temp.icns"
    local cover_file=""
    
    echo "Extracting ICNS from oggh file..." >&2
    
    # 提取ICNS资源（分离管道执行和错误检查）
    derez -only icns "$input_file" 2>/dev/null | \
         grep -o '"[[:xdigit:][:space:]]\+"' | \
         sed 's/"//g' | \
         tr -d ' \t\n' | \
         xxd -r -p > "$icns_file" 2>/dev/null
    
    # 验证ICNS文件
    if [[ ! -s "$icns_file" ]]; then
        echo "Error: ICNS file is empty or failed to extract" >&2
        return 1
    fi
    
    echo "ICNS file extracted successfully ($(stat -f%z "$icns_file") bytes)" >&2
    
    # 提取图片文件
    echo "Converting ICNS to PNG..." >&2
    if ! icnsutil e "$icns_file" -o "$tmp_dir/" 2>/dev/null; then
        echo "Error: Failed to extract images from ICNS" >&2
        rm -f "$icns_file"
        return 1
    fi
    
    # 清理临时ICNS文件
    rm -f "$icns_file"
    
    # 查找最佳分辨率的封面
    for size in 512x512 256x256 128x128 64x64 32x32; do
        if [[ -f "$tmp_dir/${size}.png" ]]; then
            cover_file="$tmp_dir/${size}.png"
            echo "Using ${size} cover image" >&2
            break
        fi
    done
    
    if [[ -z "$cover_file" ]]; then
        echo "Error: No suitable cover image found" >&2
        return 1
    fi
    
    echo "$cover_file"
    return 0
}

# 主程序开始
echo "Starting oggh to mp3 conversion..."

# 检查依赖
check_dependencies

# 创建临时目录
tmp_dir="$(mktemp -d)"
if [[ ! -d "$tmp_dir" ]]; then
    echo "Error: Failed to create temporary directory"
    exit 1
fi

# 设置清理函数
cleanup() {
    echo "Cleaning up temporary files..."
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

# 获取输出文件名（去掉扩展名）
base_name="${file%.*}"
mp3_file="${base_name}.mp3"
final_mp3="${base_name}_with_cover.mp3"

echo "Converting audio to MP3..."
# 将原始文件转换为MP3
if ! ffmpeg -i "$file" -vn -ar 44100 -ac 2 -codec:a libmp3lame -qscale:a 2 -id3v2_version 3 -metadata:s:v title="Album cover" -metadata:s:v comment="Cover (front)" "$mp3_file" 2>/dev/null; then
    echo "Error: Failed to convert audio to MP3"
    exit 1
fi

echo "Audio conversion completed: $mp3_file"

# 提取专辑封面
cover_file=$(extract_oggh_cover "$file" "$tmp_dir")
extract_result=$?

if [ $extract_result -eq 0 ] && [[ -n "$cover_file" ]] && [[ -f "$cover_file" ]]; then
    echo "Embedding cover art into MP3..."
    # 合并专辑封面和MP3文件
    if ffmpeg -i "$mp3_file" -i "$cover_file" -map 0:0 -map 1:0 -c copy -id3v2_version 3 -metadata:s:v title="Album cover" -metadata:s:v comment="Cover (front)" "$final_mp3" 2>/dev/null; then
        echo "Success: Created MP3 with cover art: $final_mp3"
    else
        echo "Error: Failed to embed cover art"
        echo "MP3 file without cover available: $mp3_file"
        exit 1
    fi
else
    echo "Warning: Could not extract cover art from file"
    echo "MP3 file without cover available: $mp3_file"
fi

echo "Conversion completed successfully!"