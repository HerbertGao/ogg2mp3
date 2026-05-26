#!/bin/bash
# ogg2mp3 — Convert QQ Music .ogg/.oggh to .mp3 with cover art and metadata.
#
# Commands:
#   convert <input>    Convert a single file
#   batch <dir>        Batch-convert a directory
#   inspect <input>    Show metadata and cover info without converting
#   doctor             Check dependencies and environment
#   help | version
#
# Global conventions:
#   stdout = data, stderr = logs, exit codes: 0 ok / 1 business / 2 args / 3 deps / 130 sigint

set -eo pipefail

VERSION="2.0.0"

# ----- globals filled by subcommands -----
JSON_MODE=0
YES_MODE=0
META_ARGS=()

# ============================================================================
# logging — everything to stderr
# ============================================================================

log_info()  { [[ $JSON_MODE -eq 0 ]] && printf '%s\n' "$*" >&2 || true; }
log_warn()  { printf 'warning: %s\n' "$*" >&2; }
log_error() { printf 'error: %s\n' "$*" >&2; }

# ============================================================================
# prompt helpers
# ============================================================================

confirm() {
    local prompt="$1"
    if [[ $YES_MODE -eq 1 ]]; then return 0; fi
    if [[ ! -t 0 ]]; then
        log_error "non-interactive: pass --yes to confirm '$prompt'"
        return 1
    fi
    local ans
    read -r -p "$prompt [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

# ============================================================================
# dependency probing
# ============================================================================

tool_path() { command -v "$1" 2>/dev/null || true; }

tool_version() {
    case "$1" in
        ffmpeg|ffprobe)
            "$1" -version 2>/dev/null | head -1 | awk '{print $3}'
            ;;
        jq)
            jq --version 2>/dev/null | sed 's/^jq-//'
            ;;
        icnsutil)
            icnsutil --version 2>/dev/null | awk '{print $NF}' \
                || python3 -c 'import icnsutil; print(getattr(icnsutil,"__version__","unknown"))' 2>/dev/null
            ;;
        derez|xxd|grep|sed)
            echo "system"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

REQUIRED_TOOLS=(ffmpeg ffprobe derez icnsutil jq xxd grep sed)

run_doctor_checks() {
    # populates parallel arrays NAMES FOUND PATHS VERSIONS
    DOCTOR_NAMES=()
    DOCTOR_FOUND=()
    DOCTOR_PATHS=()
    DOCTOR_VERSIONS=()
    local t p v
    for t in "${REQUIRED_TOOLS[@]}"; do
        p=$(tool_path "$t")
        if [[ -n "$p" ]]; then
            v=$(tool_version "$t")
            DOCTOR_FOUND+=(1)
        else
            v=""
            DOCTOR_FOUND+=(0)
        fi
        DOCTOR_NAMES+=("$t")
        DOCTOR_PATHS+=("$p")
        DOCTOR_VERSIONS+=("$v")
    done
}

install_hint() {
    case "$1" in
        ffmpeg|ffprobe) echo "brew install ffmpeg" ;;
        jq)             echo "brew install jq" ;;
        icnsutil)       echo "pip3 install icnsutil" ;;
        derez)          echo "xcode-select --install" ;;
        *)              echo "" ;;
    esac
}

# Quick precheck used by non-doctor commands. Exits 3 on missing required tools.
require_tools() {
    local missing=()
    local t
    for t in "$@"; do
        if [[ -z "$(tool_path "$t")" ]]; then
            missing+=("$t")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "missing tools: ${missing[*]} — run \`$0 doctor\` for details"
        exit 3
    fi
}

# ============================================================================
# metadata extraction
# ============================================================================

# Writes key=value lines (one per line) to $2; returns 0 if any lines written.
extract_metadata() {
    local input="$1"
    local out="$2"

    ffprobe -v quiet -print_format json -show_format -show_streams "$input" 2>/dev/null \
        | jq -r '
            ((.streams // []) | map(.tags // {}) | add // {})
            + ((.format // {}).tags // {})
            | to_entries[]?
            | select(.value != null and .value != "")
            | "\(.key)=\(.value)"
          ' > "$out" 2>/dev/null || true

    [[ -s "$out" ]]
}

# Reads $1 (metadata file) and populates the global META_ARGS array.
build_metadata_args() {
    META_ARGS=()
    local meta_file="$1"
    [[ -s "$meta_file" ]] || return 0

    local raw_key key value
    while IFS='=' read -r raw_key value; do
        [[ -z "$raw_key" || "$raw_key" =~ ^# ]] && continue
        key=$(printf '%s' "$raw_key" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')
        # trim surrounding whitespace
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        [[ -z "$value" ]] && continue

        case "$key" in
            title)               META_ARGS+=(-metadata "title=$value") ;;
            artist|albumartist)  META_ARGS+=(-metadata "artist=$value") ;;
            album)               META_ARGS+=(-metadata "album=$value") ;;
            date|year)           META_ARGS+=(-metadata "date=$value") ;;
            genre)               META_ARGS+=(-metadata "genre=$value") ;;
            track|tracknumber)   META_ARGS+=(-metadata "track=$value") ;;
            comment|description) META_ARGS+=(-metadata "comment=$value") ;;
        esac
    done < "$meta_file"
}

# ============================================================================
# cover extraction
# ============================================================================

# Echoes the path to the chosen PNG cover on stdout; non-zero exit on failure.
extract_cover() {
    local input="$1"
    local tmp_dir="$2"
    local icns="$tmp_dir/cover.icns"

    derez -only icns "$input" 2>/dev/null \
        | grep -o '"[[:xdigit:][:space:]]\+"' \
        | sed 's/"//g' \
        | tr -d ' \t\n' \
        | xxd -r -p > "$icns" 2>/dev/null

    [[ -s "$icns" ]] || return 1

    icnsutil e "$icns" -o "$tmp_dir/" >/dev/null 2>&1 || return 1
    rm -f "$icns"

    # ICNS subtypes don't all decode as real PNG even when icnsutil names them .png
    # (e.g. JPEG-2000 chunks named ic08/ic09 saved with .png). Validate with ffmpeg
    # by attempting to decode a single frame; skip any candidate ffmpeg can't read.
    local candidate
    for candidate in \
        "$tmp_dir/512x512@2x.png" "$tmp_dir/512x512.png" \
        "$tmp_dir/256x256@2x.png" "$tmp_dir/256x256.png" \
        "$tmp_dir/128x128@2x.png" "$tmp_dir/128x128.png" \
        "$tmp_dir/64x64@2x.png"   "$tmp_dir/64x64.png" \
        "$tmp_dir/32x32@2x.png"   "$tmp_dir/32x32.png"; do
        if [[ -f "$candidate" ]] \
            && ffmpeg -v error -i "$candidate" -frames:v 1 -f null - >/dev/null 2>&1; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

# ============================================================================
# single-file conversion core
# ============================================================================

# Args: input output [no_cover=0] [no_metadata=0]
# Returns 0 on success, populates globals: CONV_COVER_USED, CONV_META_COUNT
do_convert_file() {
    local input="$1"
    local output="$2"
    local no_cover="${3:-0}"
    local no_metadata="${4:-0}"

    CONV_COVER_USED=0
    CONV_META_COUNT=0

    local tmp_dir
    tmp_dir=$(mktemp -d) || { log_error "mktemp failed"; return 1; }

    META_ARGS=()
    if [[ "$no_metadata" -eq 0 ]]; then
        local meta_file="$tmp_dir/metadata.txt"
        extract_metadata "$input" "$meta_file" || true
        build_metadata_args "$meta_file"
        CONV_META_COUNT=$(( ${#META_ARGS[@]} / 2 ))
    fi

    local cover=""
    if [[ "$no_cover" -eq 0 ]]; then
        cover=$(extract_cover "$input" "$tmp_dir" 2>/dev/null) || cover=""
    fi

    local rc=0
    if [[ -n "$cover" && -f "$cover" ]]; then
        CONV_COVER_USED=1
        ffmpeg -y -i "$input" -i "$cover" \
            -map 0:a -map 1:v \
            -c:a libmp3lame -qscale:a 2 -ar 44100 -ac 2 \
            -c:v copy \
            -id3v2_version 3 \
            -metadata:s:v title="Album cover" \
            -metadata:s:v comment="Cover (front)" \
            "${META_ARGS[@]}" \
            "$output" >"$tmp_dir/ffmpeg.log" 2>&1 || rc=$?
    else
        ffmpeg -y -i "$input" -vn \
            -c:a libmp3lame -qscale:a 2 -ar 44100 -ac 2 \
            -id3v2_version 3 \
            "${META_ARGS[@]}" \
            "$output" >"$tmp_dir/ffmpeg.log" 2>&1 || rc=$?
    fi

    if [[ $rc -ne 0 ]]; then
        log_error "ffmpeg failed (exit $rc)"
        sed 's/^/  ffmpeg: /' "$tmp_dir/ffmpeg.log" >&2 || true
        rm -rf "$tmp_dir"
        return 1
    fi

    rm -rf "$tmp_dir"
    return 0
}

# ============================================================================
# cmd: convert
# ============================================================================

usage_convert() {
    cat >&2 <<'EOF'
Usage: ogg2mp3 convert <input> [flags]

Flags:
    -o, --output <path>   Output file (default: <input-base>.mp3 next to input)
    --no-cover            Skip cover art embedding
    --no-metadata         Skip metadata copying
    --overwrite           Overwrite existing output without prompting
    --json                Emit JSON result to stdout
    --yes                 Skip interactive confirmations
    -h, --help            Show this help
EOF
}

cmd_convert() {
    local input="" output="" no_cover=0 no_metadata=0 overwrite=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -o|--output)   output="$2"; shift 2 ;;
            --no-cover)    no_cover=1; shift ;;
            --no-metadata) no_metadata=1; shift ;;
            --overwrite)   overwrite=1; shift ;;
            --json)        JSON_MODE=1; shift ;;
            --yes)         YES_MODE=1; shift ;;
            -h|--help)     usage_convert; exit 0 ;;
            --)            shift; break ;;
            -*)            log_error "unknown flag: $1"; usage_convert; exit 2 ;;
            *)             if [[ -z "$input" ]]; then input="$1"; else log_error "unexpected arg: $1"; exit 2; fi; shift ;;
        esac
    done

    [[ -n "$input" ]] || { log_error "missing <input>"; usage_convert; exit 2; }
    [[ -f "$input" ]] || { log_error "input not found: $input"; exit 1; }

    require_tools ffmpeg ffprobe jq
    [[ $no_cover -eq 0 ]] && require_tools derez icnsutil xxd grep sed

    if [[ -z "$output" ]]; then
        output="${input%.*}.mp3"
    fi

    if [[ -e "$output" && $overwrite -eq 0 ]]; then
        if ! confirm "output exists: $output — overwrite?"; then
            log_error "aborted (output exists)"
            exit 1
        fi
    fi

    log_info "→ converting: $input"
    log_info "→ output:     $output"

    if ! do_convert_file "$input" "$output" "$no_cover" "$no_metadata"; then
        exit 1
    fi

    if [[ $JSON_MODE -eq 1 ]]; then
        jq -n \
            --arg input "$input" \
            --arg output "$output" \
            --argjson cover "$CONV_COVER_USED" \
            --argjson meta "$CONV_META_COUNT" \
            '{ok:true, input:$input, output:$output, cover_embedded: ($cover==1), metadata_fields:$meta}'
    else
        printf '%s\n' "$output"
        log_info "✓ done — cover=$([[ $CONV_COVER_USED -eq 1 ]] && echo yes || echo no), metadata_fields=$CONV_META_COUNT"
    fi
}

# ============================================================================
# cmd: batch
# ============================================================================

usage_batch() {
    cat >&2 <<'EOF'
Usage: ogg2mp3 batch <dir> [flags]

Flags:
    -r, --recursive       Recurse into subdirectories
    --skip-existing       Skip files whose .mp3 already exists
    --overwrite           Overwrite existing .mp3 files
    --no-cover            Skip cover art for all files
    --no-metadata         Skip metadata for all files
    --dry-run             List planned conversions without executing
    --json                Emit NDJSON (one object per file) to stdout
    --yes                 Skip confirmations
    -h, --help            Show this help

Notes:
    --skip-existing and --overwrite are mutually exclusive.
    Without either, an existing .mp3 causes that file to fail (FAIL line / ok:false).
EOF
}

cmd_batch() {
    local dir="" recursive=0 skip_existing=0 overwrite=0
    local no_cover=0 no_metadata=0 dry_run=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--recursive)  recursive=1; shift ;;
            --skip-existing) skip_existing=1; shift ;;
            --overwrite)     overwrite=1; shift ;;
            --no-cover)      no_cover=1; shift ;;
            --no-metadata)   no_metadata=1; shift ;;
            --dry-run)       dry_run=1; shift ;;
            --json)          JSON_MODE=1; shift ;;
            --yes)           YES_MODE=1; shift ;;
            -h|--help)       usage_batch; exit 0 ;;
            --)              shift; break ;;
            -*)              log_error "unknown flag: $1"; usage_batch; exit 2 ;;
            *)               if [[ -z "$dir" ]]; then dir="$1"; else log_error "unexpected arg: $1"; exit 2; fi; shift ;;
        esac
    done

    [[ -n "$dir" ]] || { log_error "missing <dir>"; usage_batch; exit 2; }
    [[ -d "$dir" ]] || { log_error "not a directory: $dir"; exit 1; }
    if [[ $skip_existing -eq 1 && $overwrite -eq 1 ]]; then
        log_error "--skip-existing and --overwrite are mutually exclusive"
        exit 2
    fi

    require_tools ffmpeg ffprobe jq
    [[ $no_cover -eq 0 ]] && require_tools derez icnsutil xxd grep sed

    # collect files
    local files=()
    local f
    if [[ $recursive -eq 1 ]]; then
        while IFS= read -r -d '' f; do files+=("$f"); done \
            < <(find "$dir" -type f \( -iname '*.ogg' -o -iname '*.oggh' \) -print0)
    else
        while IFS= read -r -d '' f; do files+=("$f"); done \
            < <(find "$dir" -maxdepth 1 -type f \( -iname '*.ogg' -o -iname '*.oggh' \) -print0)
    fi

    if [[ ${#files[@]} -eq 0 ]]; then
        log_warn "no .ogg/.oggh files found in $dir"
        exit 0
    fi

    log_info "→ found ${#files[@]} file(s) in $dir"

    local total_fail=0
    for f in "${files[@]}"; do
        local out="${f%.*}.mp3"
        local action="convert"
        local reason=""

        if [[ -e "$out" ]]; then
            if [[ $skip_existing -eq 1 ]]; then
                action="skip"; reason="exists"
            elif [[ $overwrite -eq 0 ]]; then
                action="fail"; reason="output exists (use --overwrite or --skip-existing)"
                total_fail=$((total_fail + 1))
            fi
        fi

        if [[ $dry_run -eq 1 ]]; then
            if [[ $JSON_MODE -eq 1 ]]; then
                jq -n --arg input "$f" --arg output "$out" --arg action "$action" --arg reason "$reason" \
                    '{
                        input: $input,
                        output: $output,
                        planned_action: $action,
                        reason: (if $reason == "" then null else $reason end)
                    }'
            else
                printf '%-7s %s\n' "$action" "$out"
                [[ -n "$reason" ]] && log_info "        ($reason)"
            fi
            continue
        fi

        if [[ "$action" == "skip" ]]; then
            if [[ $JSON_MODE -eq 1 ]]; then
                jq -n --arg input "$f" --arg output "$out" '{ok:true, skipped:true, input:$input, output:$output}'
            else
                printf 'SKIP\t%s\n' "$out"
            fi
            continue
        fi

        if [[ "$action" == "fail" ]]; then
            if [[ $JSON_MODE -eq 1 ]]; then
                jq -n --arg input "$f" --arg output "$out" --arg err "$reason" '{ok:false, input:$input, output:$output, error:$err}'
            else
                printf 'FAIL\t%s\t%s\n' "$out" "$reason"
            fi
            continue
        fi

        log_info "→ [$f] → [$out]"
        if do_convert_file "$f" "$out" "$no_cover" "$no_metadata"; then
            if [[ $JSON_MODE -eq 1 ]]; then
                jq -n \
                    --arg input "$f" --arg output "$out" \
                    --argjson cover "$CONV_COVER_USED" \
                    --argjson meta "$CONV_META_COUNT" \
                    '{ok:true, input:$input, output:$output, cover_embedded:($cover==1), metadata_fields:$meta}'
            else
                printf 'OK\t%s\n' "$out"
            fi
        else
            total_fail=$((total_fail + 1))
            if [[ $JSON_MODE -eq 1 ]]; then
                jq -n --arg input "$f" --arg output "$out" '{ok:false, input:$input, output:$output, error:"conversion failed"}'
            else
                printf 'FAIL\t%s\tconversion failed\n' "$out"
            fi
        fi
    done

    if [[ $total_fail -gt 0 ]]; then
        log_error "$total_fail file(s) failed"
        exit 1
    fi
}

# ============================================================================
# cmd: inspect
# ============================================================================

usage_inspect() {
    cat >&2 <<'EOF'
Usage: ogg2mp3 inspect <input> [--json]
EOF
}

cmd_inspect() {
    local input=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)    JSON_MODE=1; shift ;;
            -h|--help) usage_inspect; exit 0 ;;
            -*)        log_error "unknown flag: $1"; usage_inspect; exit 2 ;;
            *)         if [[ -z "$input" ]]; then input="$1"; else log_error "unexpected arg: $1"; exit 2; fi; shift ;;
        esac
    done

    [[ -n "$input" ]] || { log_error "missing <input>"; usage_inspect; exit 2; }
    [[ -f "$input" ]] || { log_error "input not found: $input"; exit 1; }

    require_tools ffprobe jq

    local tmp_dir
    tmp_dir=$(mktemp -d) || { log_error "mktemp failed"; exit 1; }
    trap 'rm -rf "$tmp_dir"' EXIT

    # probe audio
    local probe_json
    probe_json=$(ffprobe -v quiet -print_format json -show_format -show_streams "$input" 2>/dev/null || true)
    if [[ -z "$probe_json" ]]; then
        log_error "ffprobe failed to read: $input"
        exit 1
    fi

    # metadata
    local meta_json
    meta_json=$(printf '%s' "$probe_json" | jq -c '
        ((.streams // []) | map(.tags // {}) | add // {})
        + ((.format // {}).tags // {})
    ' 2>/dev/null || echo '{}')

    local duration codec bitrate
    duration=$(printf '%s' "$probe_json" | jq -r '.format.duration // ""')
    bitrate=$(printf '%s' "$probe_json" | jq -r '.format.bit_rate // ""')
    codec=$(printf '%s' "$probe_json" | jq -r '.streams[0].codec_name // ""')

    # cover (only attempt if cover tools available)
    local cover_present=false cover_size=0
    if [[ -n "$(tool_path derez)" && -n "$(tool_path icnsutil)" && -n "$(tool_path xxd)" ]]; then
        local cover_path
        if cover_path=$(extract_cover "$input" "$tmp_dir" 2>/dev/null) && [[ -f "$cover_path" ]]; then
            cover_present=true
            cover_size=$(stat -f%z "$cover_path" 2>/dev/null || stat -c%s "$cover_path" 2>/dev/null || echo 0)
        fi
    fi

    if [[ $JSON_MODE -eq 1 ]]; then
        jq -n \
            --arg file "$input" \
            --arg codec "$codec" \
            --arg duration "$duration" \
            --arg bitrate "$bitrate" \
            --argjson meta "$meta_json" \
            --argjson cover_present "$cover_present" \
            --argjson cover_size "$cover_size" \
            '{
                file: $file,
                codec: (if $codec == "" then null else $codec end),
                duration_sec: ($duration | tonumber? // null),
                bitrate: ($bitrate | tonumber? // null),
                metadata: $meta,
                cover: { present: $cover_present, size_bytes: $cover_size }
            }'
    else
        printf 'file:        %s\n' "$input"
        printf 'codec:       %s\n' "${codec:-?}"
        printf 'duration:    %s sec\n' "${duration:-?}"
        printf 'bitrate:     %s bps\n' "${bitrate:-?}"
        printf 'cover:       %s' "$cover_present"
        [[ $cover_size -gt 0 ]] && printf ' (%s bytes)' "$cover_size"
        printf '\n'
        printf 'metadata:\n'
        printf '%s' "$meta_json" | jq -r 'to_entries[]? | "  \(.key)=\(.value)"'
    fi
}

# ============================================================================
# cmd: doctor
# ============================================================================

usage_doctor() {
    cat >&2 <<'EOF'
Usage: ogg2mp3 doctor [--json]
EOF
}

cmd_doctor() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)    JSON_MODE=1; shift ;;
            -h|--help) usage_doctor; exit 0 ;;
            *)         log_error "unexpected arg: $1"; exit 2 ;;
        esac
    done

    run_doctor_checks

    local i ok=1
    if [[ $JSON_MODE -eq 1 ]]; then
        local checks="[]"
        for i in "${!DOCTOR_NAMES[@]}"; do
            local name="${DOCTOR_NAMES[$i]}"
            local found="${DOCTOR_FOUND[$i]}"
            local path="${DOCTOR_PATHS[$i]}"
            local ver="${DOCTOR_VERSIONS[$i]}"
            local hint
            hint=$(install_hint "$name")
            [[ $found -eq 0 ]] && ok=0
            checks=$(printf '%s' "$checks" | jq \
                --arg name "$name" \
                --argjson found "$found" \
                --arg path "$path" \
                --arg version "$ver" \
                --arg hint "$hint" \
                '. + [{
                    name: $name,
                    found: ($found==1),
                    path: (if $path == "" then null else $path end),
                    version: (if $version == "" then null else $version end),
                    install_hint: (if $hint == "" then null else $hint end)
                }]')
        done
        jq -n --argjson ok "$ok" --argjson checks "$checks" '{ok:($ok==1), checks:$checks}'
        [[ $ok -eq 1 ]] || exit 3
    else
        printf '%-12s %-8s %-12s %s\n' "TOOL" "STATUS" "VERSION" "PATH"
        for i in "${!DOCTOR_NAMES[@]}"; do
            local name="${DOCTOR_NAMES[$i]}"
            local found="${DOCTOR_FOUND[$i]}"
            local path="${DOCTOR_PATHS[$i]}"
            local ver="${DOCTOR_VERSIONS[$i]}"
            if [[ $found -eq 1 ]]; then
                printf '%-12s %-8s %-12s %s\n' "$name" "ok" "${ver:-?}" "$path"
            else
                ok=0
                local hint
                hint=$(install_hint "$name")
                printf '%-12s %-8s %-12s %s\n' "$name" "MISSING" "-" "${hint:-(install required)}"
            fi
        done
        if [[ $ok -eq 1 ]]; then
            log_info ""
            log_info "all dependencies satisfied"
        else
            log_error "one or more dependencies missing"
            exit 3
        fi
    fi
}

# ============================================================================
# interactive (no args)
# ============================================================================

interactive_menu() {
    cat >&2 <<EOF
ogg2mp3 $VERSION — interactive mode

Pick:
  1) convert a single file
  2) batch convert a directory
  3) inspect a file
  4) doctor (check dependencies)
  q) quit

EOF
    local choice
    read -r -p "> " choice
    case "$choice" in
        1)
            local f
            read -r -p "input file: " f
            cmd_convert "$f"
            ;;
        2)
            local d
            read -r -p "directory: " d
            cmd_batch "$d"
            ;;
        3)
            local f
            read -r -p "input file: " f
            cmd_inspect "$f"
            ;;
        4) cmd_doctor ;;
        q|Q|"") exit 0 ;;
        *) log_error "unknown choice: $choice"; exit 2 ;;
    esac
}

# ============================================================================
# dispatch
# ============================================================================

usage() {
    cat >&2 <<EOF
ogg2mp3 $VERSION — QQ Music .ogg/.oggh → .mp3 with cover art and metadata

USAGE
    ogg2mp3 <command> [args] [flags]
    ogg2mp3                       # interactive menu

COMMANDS
    convert <input>                Convert a single file
    batch <dir>                    Batch-convert a directory
    inspect <input>                Show metadata and cover info
    doctor                         Check dependencies and environment
    help                           Show this help
    version                        Print version

Run \`ogg2mp3 <command> --help\` for command-specific flags.
EOF
}

trap 'exit 130' INT

main() {
    if [[ $# -eq 0 ]]; then
        interactive_menu
        return $?
    fi
    local cmd="$1"; shift
    case "$cmd" in
        convert)            cmd_convert "$@" ;;
        batch)              cmd_batch "$@" ;;
        inspect)            cmd_inspect "$@" ;;
        doctor)             cmd_doctor "$@" ;;
        help|-h|--help)     usage ;;
        version|--version)  printf 'ogg2mp3 %s\n' "$VERSION" ;;
        *)                  log_error "unknown command: $cmd"; usage; exit 2 ;;
    esac
}

main "$@"
