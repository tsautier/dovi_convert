#!/usr/bin/env bash

# =============================================================================
# dovi_convert - Dolby Vision Profile 7 -> 8.1 Converter (v6.3)
#
# DESCRIPTION:
#   This tool automates the conversion of Dolby Vision Profile 7 MKV files (UHD Blu-ray)
#   into Profile 8.1. This ensures compatibility with devices that do not support the
#   Enhancement Layer (Apple TV 4K, Shield, etc.), preventing fallback to HDR and other issues.
#
# KEY FEATURES:
#   - Safe Mode: Never modifies the original file in place (creates specific backup).
#   - FPS Enforcement: Fixes mkvmerge's tendency to default raw streams to 25fps.
#   - Verification: Compares frame counts before swapping files to prevent data loss.
#   - Batch Processing: Recursively scans and converts entire libraries.
#   - Smart Cleanup: Only deletes backups created by this specific tool, and only
#     if the parent file still exists.
#
# DEPENDENCIES:
#   mkvmerge, mkvextract (MKVToolNix), dovi_tool, mediainfo, jq, bc
# =============================================================================

# --- Configuration & Constants ---
BOLD="\033[1m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

# Default Runtime Flags
VERBOSE_MODE=false      # Toggled by -v
BATCH_RUNNING=false     # Internal state flag
DELETE_BACKUP=false     # Toggled by -delete (Caution: Destructive)

# --- Pre-Flight: Safety Check ---
# Prevents "shell-init: error retrieving current directory" if the user
# runs the script from a directory that was deleted/replaced (common in testing).
if ! pwd > /dev/null 2>&1; then
    echo -e "${RED}Error: Your terminal is in a 'ghost' directory.${RESET}"
    echo "Please run 'cd .' or restart your terminal."
    exit 1
fi

# --- Pre-Flight: Dependency Check ---
# Ensures all required binaries are installed and accessible in the system PATH.
for tool in mkvmerge mkvextract dovi_tool mediainfo jq bc; do
    if ! command -v "$tool" &> /dev/null; then
        echo -e "${RED}Error: Missing dependency '$tool'.${RESET}"
        echo "Please install it using your system's package manager."
        exit 1
    fi
done

# --- Helper Functions ---

# Convert bytes to human-readable MB/GB
human_size() {
    echo $(echo "scale=2; $1/1024/1024" | bc) "MB"
}
human_size_gb() {
    echo $(echo "scale=2; $1/1024/1024/1024" | bc) "GB"
}

# Send macOS system notification (No-op on Linux/Windows)
send_notification() {
    local title="$1"
    local message="$2"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        osascript -e "display notification \"$message\" with title \"$title\" sound name \"Glass\"" 2>/dev/null
    fi
}

# Concise usage guide (Default output)
print_usage() {
    echo -e "${BOLD}dovi_convert - Dolby Vision Profile 7 -> 8.1 Converter${RESET}"
    echo "Usage:"
    echo "  dovi_convert -check             : Analyze all files in current folder."
    echo "  dovi_convert -check [file]      : Analyze a specific file."
    echo "  dovi_convert -check -r [depth]  : Recursively analyze files (default depth: 3)."
    echo "  dovi_convert -convert [file]    : Convert a file (Safe Mode: Creates .bak.dovi_convert)."
    echo "  dovi_convert -batch [depth]     : Convert ALL P7 files in folder (default depth: 1)."
    echo "  dovi_convert -cleanup           : Find and delete tool-specific backups."
    echo "  dovi_convert -help              : Show detailed manual and explanations."
    echo ""
    echo "Options:"
    echo "  -delete                         : Auto-delete the Original Source (.bak) after success."
    echo "  -v                              : Debug mode (shows verbose output)."
    echo ""
    echo "Examples:"
    echo "  dovi_convert -batch 5 -delete   : Batch convert and delete originals upon success."
    echo "  dovi_convert -convert movie.mkv : Convert and keep original as backup."
}

# Detailed manual page (Triggered by -help)
print_help() {
    echo -e "${BOLD}dovi_convert - Dolby Vision Profile 7 -> 8.1 Converter${RESET}"
    echo ""
    echo -e "${BOLD}DESCRIPTION${RESET}"
    echo "  This tool automates the conversion of Dolby Vision Profile 7 MKV files (UHD Blu-ray)"
    echo "  into Profile 8.1. This ensures compatibility with devices that do not support the"
    echo "  Enhancement Layer (Apple TV 4K, Shield, etc.), preventing fallback to HDR and other issues."
    echo ""
    echo -e "${BOLD}BACKUP STRATEGY${RESET}"
    echo "  The tool uses a specific naming convention to prevent accidental deletion of manual backups."
    echo -e "  Backup File: ${CYAN}[filename].mkv.bak.dovi_convert${RESET}"
    echo ""
    echo -e "${BOLD}HOW IT WORKS${RESET}"
    echo -e "  1. ${BOLD}Extracts${RESET} the HEVC video track."
    echo -e "  2. ${BOLD}Converts${RESET} the metadata (RPU) to Profile 8.1 and discards the unused EL."
    echo -e "  3. ${BOLD}Muxes${RESET} a new MKV, cloning all audio/subs and enforcing the original FPS."
    echo -e "  4. ${BOLD}Verifies${RESET} that the new file has the exact frame count as the source."
    echo -e "  5. ${BOLD}Swaps${RESET} the new file with the original. The original is renamed to backup."
    echo ""
    echo -e "${BOLD}COMMANDS${RESET}"
    echo ""
    echo -e "  ${BOLD}-check [file]${RESET}"
    echo "      Analyzes the Dolby Vision profile of a file."
    echo -e "      Use ${BOLD}-check -r [depth]${RESET} to scan folders recursively."
    echo ""
    echo -e "  ${BOLD}-convert [file]${RESET}"
    echo "      Converts a single file. Safe Mode is active by default:"
    echo -e "      The original file is NOT deleted; it is renamed to ${CYAN}*.mkv.bak.dovi_convert${RESET}."
    echo ""
    echo -e "  ${BOLD}-batch [depth]${RESET}"
    echo "      Recursively finds and converts all Profile 7 files in the current folder"
    echo "      and subfolders (up to 'depth' levels deep)."
    echo ""
    echo -e "  ${BOLD}-cleanup${RESET}"
    echo -e "      Scans for ${CYAN}*.mkv.bak.dovi_convert${RESET} files recursively."
    echo -e "      ${BOLD}Smart Safety:${RESET} This command checks if the 'Parent' MKV exists."
    echo "      If the main movie file is missing, the backup is treated as an 'Orphan'"
    echo "      and will NOT be deleted, preventing accidental data loss."
    echo ""
    echo -e "${BOLD}OPTIONS${RESET}"
    echo ""
    echo -e "  ${BOLD}-delete${RESET}"
    echo -e "      ${YELLOW}Auto-Delete Mode.${RESET}"
    echo -e "      Automatically deletes the backup (Original Source) file immediately"
    echo "      after a successful conversion and verification."
    echo "      Use this for large batches where you don't have disk space to store backups."
    echo ""
    echo -e "  ${BOLD}-v${RESET}"
    echo -e "      ${YELLOW}Verbose Mode.${RESET}"
    echo "      Prints full output from mkvmerge/dovi_tool. Useful for debugging errors."
}

# Cleanup Handler (Traps Ctrl+C and script exits)
cleanup_and_exit() {
    local exit_code=${1:-1}

    # Remove large temporary files if they exist (clean slate)
    if [[ -n "$raw_hevc" ]]; then
        if [[ -f "$raw_hevc" ]] || [[ -f "$conv_hevc" ]] || [[ -f "$temp_mkv" ]]; then
            if [[ "$VERBOSE_MODE" == true ]]; then
                echo -e "\n${YELLOW}Cleaning up temporary files...${RESET}"
            fi
            rm -f "$raw_hevc" "$conv_hevc" "$temp_mkv"
        fi
    fi

    # Remove temporary log file if verbose mode is OFF
    if [[ -n "$cmd_log" && -f "$cmd_log" && "$VERBOSE_MODE" == false ]]; then
        rm -f "$cmd_log"
    fi

    # If running in batch mode, we return to the loop instead of killing the script
    if [[ "$BATCH_RUNNING" == true ]]; then
        return $exit_code
    fi
    exit $exit_code
}

trap 'cleanup_and_exit 130' SIGINT SIGTERM

# --- Analysis Logic ---
# Scans a file to determine its Dolby Vision Profile (7, 8, or 5).
# Populates global variables: VIDEO_TRACK_ID, DOVI_STATUS, ACTION.
analyze_file() {
    local file="$1"
    VIDEO_TRACK_ID=""; VIDEO_DELAY="0"; VIDEO_LANG=""; VIDEO_NAME=""; DOVI_STATUS=""; ACTION=""

    # 1. Use mkvmerge to get track ID and properties (JSON format)
    local mkv_json
    mkv_json=$(mkvmerge -J "$file")

    VIDEO_TRACK_ID=$(echo "$mkv_json" | jq -r '.tracks[] | select(.type=="video") | .id' | head -n 1)

    if [[ -z "$VIDEO_TRACK_ID" ]]; then
        DOVI_STATUS="${RED}No Video Track${RESET}"; ACTION="SKIP"; return
    fi

    # Extract useful metadata to preserve during muxing
    VIDEO_DELAY=$(echo "$mkv_json" | jq -r ".tracks[] | select(.id==$VIDEO_TRACK_ID) | .properties.minimum_timestamp // 0")
    VIDEO_LANG=$(echo "$mkv_json" | jq -r ".tracks[] | select(.id==$VIDEO_TRACK_ID) | .properties.language // \"und\"")
    VIDEO_NAME=$(echo "$mkv_json" | jq -r ".tracks[] | select(.id==$VIDEO_TRACK_ID) | .properties.track_name // empty")

    # 2. Use MediaInfo to get the specific Dolby Profile string (e.g., dvhe.07)
    local mi_json
    mi_json=$(mediainfo --Output=JSON "$file")
    local combined_info
    combined_info=$(echo "$mi_json" | jq -r '.media.track[] | select(.["@type"]=="Video") | "\(.HDR_Format) \(.HDR_Format_Profile) \(.CodecID)"' | tr '\n' ' ')

    # 3. Decision Logic
    if [[ "$combined_info" == *"dvhe.07"* ]] || [[ "$combined_info" == *"Profile 7"* ]]; then
        DOVI_STATUS="${RED}Profile 7 (FEL/MEL)${RESET}"; ACTION="CONVERT"
    elif [[ "$combined_info" == *"dvhe.08"* ]] || [[ "$combined_info" == *"Profile 8"* ]]; then
        DOVI_STATUS="${GREEN}Profile 8.1${RESET}"; ACTION="IGNORE"
    elif [[ "$combined_info" == *"dvhe.05"* ]] || [[ "$combined_info" == *"Profile 5"* ]]; then
        DOVI_STATUS="${YELLOW}Profile 5 (Stream)${RESET}"; ACTION="IGNORE"
    elif [[ "$combined_info" == *"Dolby Vision"* ]]; then
        DOVI_STATUS="${RED}Unknown Dolby Profile${RESET}"; ACTION="CONVERT"
    else
        DOVI_STATUS="${CYAN}HDR10 / SDR${RESET}"; ACTION="IGNORE"
    fi
}

# Command Wrapper
# Handles stdout/stderr redirection based on -v flag.
run_logged() {
    local cmd_log=$(mktemp)
    if [[ "$VERBOSE_MODE" == true ]]; then
        "$@"
        local status=$?
    else
        "$@" > "$cmd_log" 2>&1
        local status=$?
    fi

    if [[ $status -ne 0 ]]; then
        if [[ "$VERBOSE_MODE" == false ]]; then
            echo -e "${RED}Command Failed. Output:${RESET}"
            cat "$cmd_log"
        fi
        rm -f "$cmd_log"
        return $status
    fi
    rm -f "$cmd_log"
    return 0
}

# --- Core Conversion Logic ---

cmd_convert() {
    local file="$1"
    local mode="$2" # "manual" or "auto"

    if [[ ! -f "$file" ]]; then echo "File not found: $file"; return 1; fi
    analyze_file "$file"

    # Skip files that don't need conversion (unless forced in manual mode)
    if [[ "$ACTION" == "IGNORE" || "$ACTION" == "SKIP" ]]; then
        if [[ "$mode" == "auto" ]]; then return 2; fi
        echo -e "${YELLOW}Notice: Not Profile 7 ($file).${RESET}"
        printf "Force conversion? (y/N) "
        read -r REPLY
        if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then return 0; fi
    fi

    echo -e "${BOLD}Processing:${RESET} $file"
    base_name="${file%.*}"
    raw_hevc="${base_name}.raw.hevc"
    conv_hevc="${base_name}.p81.hevc"
    temp_mkv="${base_name}.p81.mkv"

    # NEW: Specific Backup Extension to namespace our backups
    local backup_mkv="${file}.bak.dovi_convert"

    # NEW: Safety Check - Prevent overwriting an existing tool-specific backup
    if [[ -f "$backup_mkv" ]]; then
        echo -e "${RED}Skipping: Backup file already exists.${RESET}"
        echo -e "Found: ${CYAN}$(basename "$backup_mkv")${RESET}"
        echo "Please delete or move the existing backup to proceed."
        return 1
    fi

    # --- Step 0: FPS Safety Check ---
    # We must know the exact FPS to prevent mkvmerge from defaulting to 25fps.
    # If MediaInfo cannot read the header, the file is likely corrupt -> Fail Fast.
    local fps_orig=$(mediainfo --Output="Video;%FrameRate%" "$file")
    if [[ -z "$fps_orig" ]]; then
        echo -e "${RED}Error: Could not detect Frame Rate.${RESET}"
        echo "The source file header may be corrupt or unreadable."
        cleanup_and_exit 1
        return 1
    fi

    # --- Step 1: Extraction ---
    # Extract the video track to a raw HEVC stream.
    echo -n "[1/4] Extracting track $VIDEO_TRACK_ID... "
    run_logged mkvextract "$file" tracks "$VIDEO_TRACK_ID:$raw_hevc"
    if [[ $? -ne 0 ]] || [[ ! -s "$raw_hevc" ]]; then
        echo "${RED}Failed.${RESET}"; echo -e "${YELLOW}Original file retained.${RESET}"
        cleanup_and_exit 1; return 1
    fi
    [[ "$VERBOSE_MODE" == false ]] && echo -e "${GREEN}Done.${RESET}"

    # --- Step 2: Conversion ---
    # Mode 2: Converts RPU to Profile 8.1 and discards the Enhancement Layer (EL).
    echo -n "[2/4] Converting to Profile 8.1... "
    run_logged dovi_tool -m 2 convert --discard "$raw_hevc" -o "$conv_hevc"

    if [[ $? -ne 0 ]] || [[ ! -s "$conv_hevc" ]]; then
        echo "${RED}Failed.${RESET}"; echo -e "${YELLOW}Original file retained.${RESET}"
        cleanup_and_exit 1; return 1
    fi
    [[ "$VERBOSE_MODE" == false ]] && echo -e "${GREEN}Done.${RESET}"

    # --- Step 3: Muxing ---
    # Create the new MKV. We must explicitly set --default-duration to match source FPS.
    # We also clone track names, languages, and delay properties.
    echo -n "[3/4] Muxing (Cloning Metadata + ${fps_orig}fps)... "
    local mux_args=("-o" "$temp_mkv")
    if [[ "$VIDEO_DELAY" != "0" ]]; then mux_args+=("--sync" "0:$VIDEO_DELAY"); fi
    mux_args+=("--default-duration" "0:${fps_orig}fps" "--language" "0:$VIDEO_LANG")
    if [[ -n "$VIDEO_NAME" ]]; then mux_args+=("--track-name" "0:$VIDEO_NAME"); fi
    mux_args+=("$conv_hevc" "--no-video" "$file")

    run_logged mkvmerge "${mux_args[@]}"
    if [[ $? -ne 0 ]]; then
        echo "${RED}Failed.${RESET}"; echo -e "${YELLOW}Original file retained.${RESET}"
        cleanup_and_exit 1; return 1
    fi
    [[ "$VERBOSE_MODE" == false ]] && echo -e "${GREEN}Done.${RESET}"

    # --- Step 4: Verification ---
    # Compare frame counts. Small duration mismatches (<2s) are tolerated if frames match.
    echo -n "[4/4] Verifying... "
    local frames_orig=$(mediainfo --Output="Video;%FrameCount%" "$file")
    local frames_new=$(mediainfo --Output="Video;%FrameCount%" "$temp_mkv")
    local dur_orig=$(mediainfo --Output="General;%Duration%" "$file")
    local dur_new=$(mediainfo --Output="General;%Duration%" "$temp_mkv")
    local diff_dur=$(( dur_orig - dur_new )); diff_dur=${diff_dur#-}

    if [[ $diff_dur -gt 2000 ]]; then
        if [[ "$frames_orig" == "$frames_new" ]] && [[ -n "$frames_orig" ]]; then
             echo -e "${YELLOW}Duration mismatch but FRAMES MATCH. Safe.${RESET}"
        else
             echo -e "${RED}FAIL: Frame/Duration mismatch!${RESET}"
             echo -e "Original: $frames_orig | New: $frames_new"
             echo -e "${YELLOW}Original file retained.${RESET}"
             cleanup_and_exit 1; return 1
        fi
    fi

    # --- Step 5: Atomic Swap ---
    # Rename Original -> .bak.dovi_convert
    # Rename New -> Original
    mv "$file" "$backup_mkv"
    mv "$temp_mkv" "$file"
    echo -e "${GREEN}Success!${RESET}"

    # Handle Auto-Deletion (-delete flag)
    if [[ "$DELETE_BACKUP" == true ]]; then
        rm "$backup_mkv"
        echo -e "${YELLOW}Original Source deleted (-delete active).${RESET}"
    else
        echo -e "Original Source saved as: ${CYAN}${backup_mkv}${RESET}"
    fi

    rm -f "$raw_hevc" "$conv_hevc"
    return 0
}

# --- Cleanup Logic (Smart Disk Sweep) ---
cmd_cleanup() {
    echo -e "${BOLD}Scanning for .bak.dovi_convert files...${RESET}"
    local files=()
    local total_size=0

    # 1. Find all files ending in our specific backup extension
    while IFS= read -r -d '' f; do

        # 2. PARENT CHECK: Identify the main file
        #    "${f%.bak.dovi_convert}" removes the suffix to find the parent
        local parent_file="${f%.bak.dovi_convert}"

        if [[ -f "$parent_file" ]]; then
            # Parent exists, so this backup is safe to offer for deletion
            files+=("$f")
            local size=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f") # BSD/GNU stat compat
            total_size=$((total_size + size))
        else
            # Parent missing - Treat as Orphan and Skip
            echo -e "${YELLOW}Skipping Orphan Backup (Parent Missing):${RESET} $(basename "$f")"
        fi
    done < <(find . -name "*.mkv.bak.dovi_convert" -print0)

    if [[ ${#files[@]} -eq 0 ]]; then echo "No valid backup files found."; return 0; fi

    local size_gb=$(human_size_gb $total_size)
    echo -e "Found ${BOLD}${#files[@]} valid backups${RESET} utilizing ${BOLD}${size_gb}${RESET}."
    echo ""
    echo -e "${RED}WARNING: These are your ORIGINAL SOURCE FILES.${RESET}"
    echo "Deletion is permanent and cannot be undone."
    echo ""
    printf "Are you sure you want to delete them? (y/N) "
    read -r REPLY
    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        for f in "${files[@]}"; do rm "$f"; echo "Deleted: $(basename "$f")"; done
        echo -e "${GREEN}Cleanup complete. Reclaimed $size_gb.${RESET}"
    else
        echo "Cancelled."
    fi
}

# --- Batch Processing Logic ---
cmd_batch() {
    local max_depth="${1:-1}"
    BATCH_RUNNING=true
    local conversion_queue=(); local processed_count=0; local skipped_count=0; local success_list=(); local fail_list=()

    echo -e "${BOLD}Scanning for Profile 7 files (Depth: $max_depth)...${RESET}"
    while IFS= read -r -d '' file; do
        analyze_file "$file"
        if [[ "$ACTION" == "CONVERT" ]]; then conversion_queue+=("$file"); else ((skipped_count++)); fi
    done < <(find . -maxdepth "$max_depth" -name "*.mkv" -print0 | sort -z)

    if [[ ${#conversion_queue[@]} -eq 0 ]]; then echo "No Profile 7 files found (Skipped: $skipped_count)."; return 0; fi

    echo -e "\n${BOLD}Files to be converted (${#conversion_queue[@]}):${RESET}"
    for f in "${conversion_queue[@]}"; do echo " - $(basename "$f")"; done
    echo "---------------------------------------------------"
    echo -e "Starting in 3 seconds... (Ctrl+C to cancel)"; sleep 3; echo ""

    # Process Loop
    for file in "${conversion_queue[@]}"; do
        echo "---------------------------------------------------"
        cmd_convert "$file" "auto"
        if [[ $? -eq 0 ]]; then success_list+=("$(basename "$file")"); else fail_list+=("$(basename "$file")"); fi
    done
    BATCH_RUNNING=false

    # Summary Report
    echo -e "\n==================================================="
    echo -e "              ${BOLD}BATCH SUMMARY${RESET}"
    echo "==================================================="
    echo -e "Skipped:    ${CYAN}$skipped_count${RESET}"
    echo -e "Processed:  ${#conversion_queue[@]}"
    echo -e "Successful: ${GREEN}${#success_list[@]}${RESET}"
    echo -e "Failed:     ${RED}${#fail_list[@]}${RESET}"
    if [[ ${#fail_list[@]} -gt 0 ]]; then
        echo "---------------------------------------------------"
        echo -e "${RED}Failed Files:${RESET}"; for f in "${fail_list[@]}"; do echo " - $f"; done
    fi
    echo "---------------------------------------------------"
    if [[ "$DELETE_BACKUP" == false ]]; then
        echo -e "Backups: ${CYAN}*.bak.dovi_convert${RESET} (Run 'dovi_convert -cleanup' to remove Originals)"
    else
        echo -e "Backups: ${YELLOW}Originals deleted automatically.${RESET}"
    fi
    echo "==================================================="
    send_notification "dovi_convert" "Batch Complete. ${#success_list[@]} Success, ${#fail_list[@]} Failed."
}

# --- Reporting Commands ---

cmd_check_single() {
    local file="$1"; analyze_file "$file"; local delay_ms=$(echo "scale=0; $VIDEO_DELAY/1000000" | bc)
    echo "---------------------------------------------------"
    echo -e "${BOLD}File:${RESET}   $(basename "$file")"
    echo -e "${BOLD}Status:${RESET} $DOVI_STATUS"
    echo -e "${BOLD}Track:${RESET}  ID $VIDEO_TRACK_ID | Lang: $VIDEO_LANG"
    echo -e "${BOLD}Delay:${RESET}  ${delay_ms}ms"
    echo -e "${BOLD}Action:${RESET} $ACTION"
    echo "---------------------------------------------------"
}

cmd_check_all() {
    local max_depth="${1:-1}"
    printf "%-50s %-25s %-10s\n" "Filename" "Profile" "Action"
    echo "----------------------------------------------------------------------------------------"
    while IFS= read -r -d '' file; do
        analyze_file "$file"
        local name="${file#./}"; if [ ${#name} -gt 48 ]; then name="${name:0:45}..."; fi
        printf "%-50s ${DOVI_STATUS} \t\t $ACTION\n" "$name"
    done < <(find . -maxdepth "$max_depth" -name "*.mkv" -print0 | sort -z)
}

# --- Main Argument Parser ---
# 1. First Pass: Extract options (-v, -delete, -help) regardless of position.
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
  case $1 in
    -v)
      VERBOSE_MODE=true
      shift ;;
    -delete)
      DELETE_BACKUP=true
      shift ;;
    -help|--help|-h)
      print_help
      exit 0 ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift ;;
  esac
done
set -- "${POSITIONAL_ARGS[@]}" # Restore positional parameters

# 2. Second Pass: Execute commands
case "$1" in
    -check)
        if [[ "$2" == "-r" ]]; then cmd_check_all "${3:-3}"
        elif [[ -n "$2" ]]; then cmd_check_single "$2"
        else cmd_check_all 1; fi ;;
    -convert)
        if [[ -z "$2" ]]; then echo "Usage: dovi_convert -convert [file]"; exit 1; fi
        cmd_convert "$2" "manual" ;;
    -batch) cmd_batch "${2:-1}" ;;
    -cleanup) cmd_cleanup ;;
    *) print_usage ;;
esac
