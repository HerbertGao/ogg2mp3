#!/bin/bash

# =============================================================================
# OGGH to MP3 Converter with Metadata and Cover Art Support
# =============================================================================
# 功能：将QQ音乐OGG文件转换为MP3格式，保留元数据和专辑封面
# 作者：HerbertGao
# 依赖：ffmpeg, ffprobe, derez, icnsutil, jq, grep, sed, xxd
# =============================================================================

# =============================================================================
# 1. 参数检查和文件验证
# =============================================================================

# 检查命令行参数
if [ $# -eq 0 ]; then
    echo "Usage: $0 <input_file.ogg>"
    echo "Please provide a file path as the argument."
    exit 1
fi

file="$1"

# 检查输入文件是否存在
if [[ ! -f "$file" ]]; then
    echo "Error: Input file '$file' not found."
    exit 1
fi

# =============================================================================
# 2. 依赖检查函数
# =============================================================================

check_dependencies() {
    local missing_tools=()
    
    echo "Checking dependencies..."
    for tool in ffmpeg derez icnsutil grep sed xxd jq; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo "Error: Missing required tools: ${missing_tools[*]}"
        echo "Please install the missing dependencies."
        exit 1
    fi
    echo "All dependencies found."
}

# =============================================================================
# 3. 元数据提取函数
# =============================================================================

extract_metadata() {
    local input_file="$1"
    local metadata_file="$2"
    
    echo "Extracting metadata from OGG file..." >&2
    
    # 方法1：使用ffprobe从流级别提取元数据
    if command -v ffprobe >/dev/null 2>&1; then
        ffprobe -v quiet -print_format json -show_format -show_streams "$input_file" 2>/dev/null | \
        jq -r '.streams[]?.tags | select(. != null) | to_entries[] | select(.value != null) | "\(.key)=\(.value)"' > "$metadata_file" 2>/dev/null
        
        if [[ -s "$metadata_file" ]]; then
            echo "Metadata extracted successfully from stream level" >&2
            return 0
        fi
        
        # 方法2：如果流级别没有元数据，尝试格式级别
        ffprobe -v quiet -print_format json -show_format "$input_file" 2>/dev/null | \
        jq -r '.format.tags | select(. != null) | to_entries[] | select(.value != null) | "\(.key)=\(.value)"' > "$metadata_file" 2>/dev/null
        
        if [[ -s "$metadata_file" ]]; then
            echo "Metadata extracted successfully from format level" >&2
            return 0
        fi
    fi
    
    # 方法3：如果ffprobe不可用，尝试使用ffmpeg
    if command -v ffmpeg >/dev/null 2>&1; then
        ffmpeg -i "$input_file" -f null - 2>&1 | \
        grep -E "^\s*(title|artist|album|date|genre|track|comment):" | \
        sed 's/^\s*//' | \
        sed 's/:/=/' > "$metadata_file" 2>/dev/null
        
        if [[ -s "$metadata_file" ]]; then
            echo "Metadata extracted successfully using ffmpeg" >&2
            return 0
        fi
    fi
    
    echo "Warning: Could not extract metadata from file" >&2
    return 1
}

# =============================================================================
# 4. 元数据参数构建函数
# =============================================================================

build_metadata_args() {
    local metadata_file="$1"
    local metadata_args=""
    
    if [[ ! -f "$metadata_file" ]] || [[ ! -s "$metadata_file" ]]; then
        echo ""
        return 0
    fi
    
    echo "Building metadata arguments..." >&2
    
    # 读取元数据文件并构建参数
    while IFS='=' read -r key value; do
        # 跳过空行和注释
        if [[ -z "$key" ]] || [[ "$key" =~ ^# ]]; then
            continue
        fi
        
        # 清理键名和值
        key=$(echo "$key" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # 跳过空值
        if [[ -z "$value" ]]; then
            continue
        fi
        
        # 映射常见的元数据字段
        case "$key" in
            "title")
                metadata_args="$metadata_args -metadata title='$value'"
                ;;
            "artist"|"albumartist")
                metadata_args="$metadata_args -metadata artist='$value'"
                ;;
            "album")
                metadata_args="$metadata_args -metadata album='$value'"
                ;;
            "date"|"year")
                metadata_args="$metadata_args -metadata date='$value'"
                ;;
            "genre")
                metadata_args="$metadata_args -metadata genre='$value'"
                ;;
            "track"|"tracknumber")
                metadata_args="$metadata_args -metadata track='$value'"
                ;;
            "comment"|"description")
                metadata_args="$metadata_args -metadata comment='$value'"
                ;;
        esac
    done < "$metadata_file"
    
    echo "$metadata_args"
}

# =============================================================================
# 5. 封面提取函数
# =============================================================================

extract_oggh_cover() {
    local input_file="$1"
    local tmp_dir="$2"
    local icns_file="$tmp_dir/temp.icns"
    local cover_file=""
    
    echo "Extracting ICNS from oggh file..." >&2
    
    # 提取ICNS资源
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

# =============================================================================
# 6. 主程序开始
# =============================================================================

echo "🚀 Starting oggh to mp3 conversion..."

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

# 获取输出文件名
base_name="${file%.*}"
mp3_file="${base_name}.mp3"
final_mp3="${base_name}_with_cover.mp3"
metadata_file="$tmp_dir/metadata.txt"

# =============================================================================
# 7. 元数据提取和处理
# =============================================================================

echo "📋 Extracting metadata from input file..."
if extract_metadata "$file" "$metadata_file"; then
    echo "✅ Metadata extracted successfully"
    # 显示提取的元数据
    if [[ -f "$metadata_file" ]] && [[ -s "$metadata_file" ]]; then
        echo "📝 Found metadata:"
        cat "$metadata_file" | sed 's/^/  /'
    fi
else
    echo "⚠️  No metadata found or failed to extract"
fi

# 构建元数据参数
metadata_args=$(build_metadata_args "$metadata_file")

# =============================================================================
# 8. 音频转换
# =============================================================================

echo "🎵 Converting audio to MP3..."
echo "Using metadata arguments: $metadata_args" >&2
if ! eval "ffmpeg -y -i \"$file\" -vn -ar 44100 -ac 2 -codec:a libmp3lame -qscale:a 2 -id3v2_version 3 $metadata_args \"$mp3_file\"" 2>/dev/null; then
    echo "❌ Error: Failed to convert audio to MP3"
    exit 1
fi

echo "✅ Audio conversion completed: $mp3_file"

# =============================================================================
# 9. 封面提取和嵌入
# =============================================================================

# 提取专辑封面
cover_file=$(extract_oggh_cover "$file" "$tmp_dir")
extract_result=$?

if [ $extract_result -eq 0 ] && [[ -n "$cover_file" ]] && [[ -f "$cover_file" ]]; then
    echo "🖼️  Embedding cover art into MP3..."
    echo "📌 Step 1: Embedding cover art first..."
    
    # 第一步：先嵌入封面（不添加元数据）
    if eval "ffmpeg -y -i \"$mp3_file\" -i \"$cover_file\" -map 0:0 -map 1:0 -c:a copy -c:v copy -id3v2_version 3 -metadata:s:v title=\"Album cover\" -metadata:s:v comment=\"Cover (front)\" \"$final_mp3\"" 2>/dev/null; then
        echo "📌 Step 2: Adding metadata to the file with cover art..."
        # 第二步：添加元数据到已包含封面的文件
        temp_final="$tmp_dir/temp_final.mp3"
        if eval "ffmpeg -y -i \"$final_mp3\" -c copy $metadata_args \"$temp_final\"" 2>/dev/null; then
            # 替换原文件
            mv "$temp_final" "$final_mp3"
            echo "🎉 Success: Created MP3 with cover art and metadata: $final_mp3"
            echo "📁 Note: Original MP3 with metadata (no cover) available at: $mp3_file"
            echo "🗑️  You can delete the intermediate file if you only want the version with cover art."
        else
            echo "⚠️  Warning: Cover art embedded successfully, but failed to add metadata"
            echo "🖼️  MP3 with cover art (no metadata) available at: $final_mp3"
            echo "📝 MP3 with metadata (no cover) available at: $mp3_file"
        fi
    else
        echo "❌ Error: Failed to embed cover art"
        echo "📁 MP3 file without cover available: $mp3_file"
        exit 1
    fi
else
    echo "⚠️  Warning: Could not extract cover art from file"
    echo "📁 MP3 file with metadata available: $mp3_file"
fi

# =============================================================================
# 10. 完成
# =============================================================================

echo "🎉 Conversion completed successfully!"