#!/usr/bin/env bash
# =============================================================================
# dovi_convert - Dolby Vision Profile 7 -> 8.1 Converter (v6.5)
#
# DESCRIPTION:
#   Automates conversion of Dolby Vision Profile 7 MKV files (UHD Blu-ray)
#   into Profile 8.1. This ensures compatibility with devices that do not support
#   the Enhancement Layer.
#
# =============================================================================

# --- Configuration & Constants ---
BOLD="\033[1m"; RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; CYAN="\033[36m"; RESET="\033[0m"

# Default Runtime Flags
DEBUG_MODE=false        # Toggled by -debug
BATCH_RUNNING=false     # Internal state flag
ABORT_REQUESTED=false   # Internal flag for Ctrl+C handling
DELETE_BACKUP=false     # Toggled by -delete
SAFE_MODE=false         # Toggled by -safe
AUTO_YES=false          # Toggled by -y

# Global Variables for Metrics
START_TIME=0
ORIG_SIZE=0

# --- Pre-Flight: Safety Check ---
if ! pwd > /dev/null 2>&1; then
    echo -e "${RED}Error: Ghost directory detected.${RESET} Please 'cd .' or restart terminal."
    exit 1
fi

# --- Pre-Flight: Dependency Check ---
for tool in mkvmerge mkvextract dovi_tool mediainfo jq bc ffmpeg; do
    if ! command -v "$tool" &> /dev/null; then
        echo -e "${RED}Error: Missing dependency '$tool'.${RESET}"
        echo "Please install it using your system's package manager."
        exit 1
    fi
done

# --- Helper Functions ---
human_size_gb() { echo $(echo "scale=2; $1/1024/1024/1024" | bc) "GB"; }
get_file_size() { stat -f%z "$1" 2>/dev/null || stat -c%s "$1"; }

send_notification() {
    local title="$1"; local message="$2"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        osascript -e "display notification \"$message\" with title \"$title\" sound name \"Glass\"" 2>/dev/null
    fi
}

print_log() {
    local msg="$1"
    echo -e "$msg"
    if [ "$DEBUG_MODE" = true ]; then
        echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" | sed 's/\x1b\[[0-9;]*m//g' >> "dovi_convert_debug.log"
    fi
}

# ------------------------------------------------------------------------------
# DEEP SCAN ANALYZER
# ------------------------------------------------------------------------------

# Analyzes the RPU of a file to detect "Active Reconstruction" (Complex FEL).
# Sets globals: FEL_VERDICT (SAFE|COMPLEX|UNKNOWN) and FEL_REASON
check_fel_complexity() {
    local file="$1"
    FEL_VERDICT="UNKNOWN"
    FEL_REASON="Analysis failed"

    # print_log "${CYAN}Running Deep Scan on: $(basename "$file")...${RESET}" # Reduced noise as requested

    # Temp file for HEVC snippet
    local temp_hevc="probe_$(date +%s)_$$.hevc"
    local temp_rpu="${temp_hevc}.rpu"

    # 1. Extract 1 second of HEVC (reliable method)
    if [[ "$DEBUG_MODE" == true ]]; then
        ffmpeg -y -i "$file" -c:v copy -bsf:v hevc_mp4toannexb -f hevc -t 1 "$temp_hevc" >> dovi_convert_debug.log 2>&1
    else
        ffmpeg -v error -y -i "$file" -c:v copy -bsf:v hevc_mp4toannexb -f hevc -t 1 "$temp_hevc" 2>/dev/null
    fi
    
    if [ ! -s "$temp_hevc" ]; then
         FEL_REASON="Probe extraction failed (ffmpeg error)"
         rm -f "$temp_hevc"
         return 1
    fi

    # 2. Extract RPU from HEVC (Detaches RPU from potentially messy slice structure)
    if [[ "$DEBUG_MODE" == true ]]; then
        dovi_tool extract-rpu "$temp_hevc" -o "$temp_rpu" >> dovi_convert_debug.log 2>&1
    else
         dovi_tool extract-rpu "$temp_hevc" -o "$temp_rpu" >/dev/null 2>&1
    fi
    
    rm -f "$temp_hevc" # Done with HEVC

    if [ ! -s "$temp_rpu" ]; then
         FEL_REASON="RPU extraction failed (No RPU found or dovi_tool error)"
         rm -f "$temp_rpu"
         return 1
    fi

    # 3. Analyze the clean RPU file
    local json_output
    # Note: dovi_tool prints "Parsing RPU file..." to stdout, corrupting JSON.
    # We use sed to strip everything before the first '{' character.
    if [[ "$DEBUG_MODE" == true ]]; then
         # In debug mode, we define json_output carefully to avoid capturing random debug text, 
         # but we want to log the raw attempt. 
         # We will run it twice? No, inefficient.
         # Just capture stderr to log.
         json_output=$(dovi_tool info -f 0 -i "$temp_rpu" 2>> dovi_convert_debug.log | sed -n '/^{/,$p')
    else
         json_output=$(dovi_tool info -f 0 -i "$temp_rpu" 2>/dev/null | sed -n '/^{/,$p')
    fi
    
    rm -f "$temp_rpu" # Done with RPU

    if [ -z "$json_output" ] || [ "$json_output" == "{" ]; then
        FEL_REASON="Could not parse RPU (dovi_tool info error or empty)"
        if [[ "$DEBUG_MODE" == true ]]; then echo "[Deep Scan Error] JSON Empty. Output: $json_output" >> dovi_convert_debug.log; fi
        return 1
    fi

    # Check for MMR (Multi-Variate Multiple Regression)
    # Using jq for robust JSON parsing
    if echo "$json_output" | jq -e '.rpu_data_mapping.curves[] | select(.mapping_idc == "MMR")' >/dev/null 2>&1; then
        FEL_VERDICT="COMPLEX"
        FEL_REASON="Active Reconstruction (MMR Mapping Detected)"
        return 0
    fi

    # Check for Active NLQ Offsets (Non-Zero)
    # If the offset array is anything other than [0,0,0], it's active reconstruction.
    if echo "$json_output" | jq -e '.rpu_data_mapping.nlq.nlq_offset | select(. != [0,0,0])' >/dev/null 2>&1; then
        FEL_VERDICT="COMPLEX"
        FEL_REASON="Active Reconstruction (Non-Zero NLQ Offsets)"
        return 0
    fi

    # If we got here: Polynomial(0) and NLQ=[0,0,0] (or NLQ missing)
    FEL_VERDICT="SAFE"
    FEL_REASON="Static / Simple FEL (Safe to Convert)"
    return 0
}

# --- UI: Robust Spinner (Cursor Hiding + Line Clearing) ---
spinner_pid=""
start_spinner() {
    local label_text="$1"
    set +m # Silence job control messages

    # 1. Hide Cursor
    printf "\e[?25l"

    # Check for UTF-8 support
    local use_braille=false
    if [[ "$LANG" == *"UTF-8"* ]] || [[ "$LC_ALL" == *"UTF-8"* ]]; then
        use_braille=true
    fi

    (
        local delay=0.1
        local spinstr
        if [[ "$use_braille" == true ]]; then
            spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
        else
            spinstr='|/-\'
        fi

        local step_start=$SECONDS
        while :; do
            local temp=${spinstr#?}
            local char=${spinstr%"$temp"}
            local elapsed=$((SECONDS - step_start))
            local min=$((elapsed / 60))
            local sec=$((elapsed % 60))

            # 2. The Animation Loop
            printf "\r\e[K%s %s (%dm %02ds)" "$label_text" "$char" "$min" "$sec"

            local spinstr=$temp$char
            sleep $delay
        done
    ) &
    spinner_pid=$!
}

stop_spinner() {
    if [[ -n "$spinner_pid" ]]; then
        kill "$spinner_pid" >/dev/null 2>&1
        wait "$spinner_pid" >/dev/null 2>&1
        spinner_pid=""
        # 3. Restore Cursor
        printf "\e[?25h"
    fi
}

# --- UI: Conversion Metrics ---
print_metrics() {
    local final_file="$1"
    local frame_count="$2"

    local duration=$((SECONDS - START_TIME))
    local min=$((duration / 60))
    local sec=$((duration % 60))

    local final_size=$(get_file_size "$final_file")
    local size_diff=$((ORIG_SIZE - final_size))

    if [[ $size_diff -lt 0 ]]; then size_diff=0; fi

    local orig_gb=$(human_size_gb $ORIG_SIZE)
    local final_gb=$(human_size_gb $final_size)

    # Dynamic Unit Logic
    local diff_disp=""
    if [[ $size_diff -ge 1073741824 ]]; then
        diff_disp="$(echo "scale=2; $size_diff/1024/1024/1024" | bc) GB"
    else
        diff_disp="$(echo "scale=2; $size_diff/1024/1024" | bc) MB"
    fi

    local fps=0
    if [[ $duration -gt 0 ]]; then fps=$((frame_count / duration)); fi

    echo "---------------------------------------------------"
    echo -e "             ${BOLD}CONVERSION METRICS${RESET}"
    echo "---------------------------------------------------"
    printf "Time Taken:    %dm %02ds\n" "$min" "$sec"
    printf "Orig Size:     %s\n" "$orig_gb"
    printf "Final Size:    %s\n" "$final_gb"
    printf "EL Discarded:  %s (Space Saved)\n" "$diff_disp"
    printf "Avg Speed:     %s fps\n" "$fps"
    echo "---------------------------------------------------"
}

# Concise usage guide
print_usage() {
    echo -e "${BOLD}dovi_convert v6.5${RESET}"
    echo "Usage:"
    echo -e "  ${BOLD}dovi_convert -help                   : SHOW DETAILED MANUAL & EXAMPLES${RESET}"
    echo "  dovi_convert -check                  : Analyze all MKV files in current directory."
    echo "  dovi_convert -check   [file]         : Analyze profile of a specific file."
    echo "  dovi_convert -inspect [file] [-safe] : Inspect full RPU structure (Active Brightness Check)."
    echo "  dovi_convert -convert [file]         : Convert a file to DV Profile 8.1."
    echo "  dovi_convert -convert [file] -safe   : Convert using Safe Mode (Disk Extraction)."
    echo "  dovi_convert -batch   [depth] [-y]   : Batch convert folder (-y to auto-confirm)."
    echo "  dovi_convert -cleanup [-r]    [-y]   : Delete tool backups (Optional: -r recursive)."
    echo ""
    echo "Options:"
    echo "  -force  : Override 'Complex FEL' warnings and force conversion."
    echo "  -safe   : Force extraction to disk (Robust for Seamless Branching rips)."
    echo "  -delete : Auto-delete backups on success."
    echo "  -debug  : Generate dovi_convert_debug.log (Preserved on exit)."
    echo "  -y      : Auto-answer 'Yes' to confirmation prompts (Batch/Cleanup)."
}

# Detailed manual page
print_help() {
    echo -e "${BOLD}dovi_convert - Dolby Vision Profile 7 -> 8.1 Converter${RESET}"
    echo ""
    echo -e "${BOLD}DESCRIPTION${RESET}"
    echo "  This tool automates the conversion of Dolby Vision Profile 7 MKV files (UHD Blu-ray)"
    echo "  into Profile 8.1. This ensures compatibility with devices that do not support the"
    echo "  Enhancement Layer (Apple TV 4K, Shield, etc.), preventing fallback to HDR10."
    echo ""
    echo -e "${BOLD}MODES OF OPERATION${RESET}"
    echo -e "  ${BOLD}1. Standard Mode (Default)${RESET}"
    echo "     Pipes the video stream directly into the conversion tool."
    echo "     Fast, efficient, and requires zero temporary disk space."
    echo ""
    echo -e "  ${BOLD}2. Safe Mode (-safe)${RESET}"
    echo "     Extracts the video track to a temporary file on disk, then converts."
    echo "     Slower, but robust against files with irregular timestamps or"
    echo "     'Seamless Branching' structures (common on Disney/Marvel discs)."
    echo "     The tool will automatically offer this mode if Standard conversion fails."
    echo ""
    echo -e "${BOLD}FEL HANDLING (DEEP SCAN)${RESET}"
    echo "  The tool automatically performs a 'Deep Scan' on all Profile 7 files."
    echo "  It analyzes the RPU metadata to distinguish between:"
    echo -e "  1. ${GREEN}Simple FEL / MEL${RESET}: Metadata-only or static. Safe to convert. (Default)"
    echo -e "  2. ${RED}Complex FEL${RESET}: Contains active 12-bit reconstruction data (MMR or NLQ)."
    echo "     Converting these files discards brightness data. The tool will SKIP them."
    echo ""
    echo -e "${BOLD}AUTOMATIC BACKUPS${RESET}"
    echo "  The tool automatically preserves your original file before any modification."
    echo "  It uses a specific naming convention to distinguish its backups from your own files."
    echo -e "  Backup File: ${CYAN}[filename].mkv.bak.dovi_convert${RESET}"
    echo ""
    echo "  The -cleanup command will ONLY target files with this specific extension."
    echo ""
    echo -e "${BOLD}KNOWN LIMITATION: Single Video Track${RESET}"
    echo -e "  The ${BOLD}converted${RESET} file will contain exactly one video track (the main movie)."
    echo "  Any secondary video streams (e.g., Picture-in-Picture commentary or Multi-Angle views)"
    echo "  will be dropped because the conversion process isolates the main video track."
    echo ""
    echo -e "  ${BOLD}No Risk of Data Loss:${RESET} Your original source file (containing all tracks)"
    echo "  is automatically preserved as a backup. You can restore it if needed."
    echo ""
    echo -e "${BOLD}COMMANDS${RESET}"
    echo ""
    echo -e "  ${BOLD}-check [file]${RESET}"
    echo "       Analyze the Dolby Vision profile of a file."
    echo "       If [file] is omitted, scans all MKV files in the current directory."
    echo "       Perfoms Deep Scan by default."
    echo ""
    echo "       Options:"
    echo -e "         ${BOLD}-r${RESET}       Recursive scan (Default depth: 5 levels. Specify number to increase)."
    echo ""
    echo -e "  ${BOLD}-convert [file]${RESET}"
    echo "       Converts a single file to Profile 8.1."
    echo "       Skips 'Complex FEL' files to prevent data loss."
    echo "       The original file is NOT deleted; it is renamed to *.mkv.bak.dovi_convert."
    echo ""
    echo "       Options:"
    echo -e "         ${BOLD}-force${RESET}   Override 'Complex FEL' detection."
    echo ""
    echo -e "  ${BOLD}-inspect [file]${RESET}"
    echo "       Inspects full RPU structure to verify brightness metadata."
    echo "       Compares Peak Brightness in RPU vs Base Layer to detect active expansion."
    echo "       Use this to verify 'Complex FEL' verdicts. (Slow: Reads entire file)."
    echo ""
    echo "       Options:"
    echo -e "         ${BOLD}-safe${RESET}    Force Safe Mode (Disk Extraction fallback)."
    echo ""
    echo -e "  ${BOLD}-batch [depth]${RESET}"
    echo "       Recursively finds and converts all Profile 7 files in the current folder"
    echo "       and subfolders (up to 'depth' levels deep)."
    echo "       Use -y to skip the interactive confirmation steps."
    echo "       Complex FELs are skipped unless overridden."
    echo ""
    echo "       Options:"
    echo -e "         ${BOLD}-y${RESET}       Skip confirmation prompts."
    echo -e "         ${BOLD}-force${RESET}   Convert Complex FELs (Apply to all)."
    echo -e "         ${BOLD}-delete${RESET}  Auto-delete backups."
    echo ""
    echo -e "  ${BOLD}-cleanup${RESET}"
    echo -e "       Scans for and deletes ${CYAN}*.mkv.bak.dovi_convert${RESET} files in the current directory."
    echo -e "       ${BOLD}Safety Check:${RESET} Checks if 'Parent' MKV exists before deleting orphan backups."
    echo ""
    echo "       Options:"
    echo -e "         ${BOLD}-r${RESET}       Recursive scan."
    echo -e "         ${BOLD}-y${RESET}       Skip confirmation prompts."
    echo ""
    echo -e "${BOLD}OPTION DETAILS${RESET}"
    echo ""
    echo -e "  ${BOLD}-force${RESET} [Convert, Batch]"
    echo -e "       ${RED}Force Conversion.${RESET}"
    echo "       Overrides the 'Complex FEL' detection. Use this if you want to convert"
    echo "       a Complex FEL file despite the potential loss of brightness data."
    echo ""

    echo -e "  ${BOLD}-safe${RESET}  [Convert, Batch]"
    echo -e "       ${YELLOW}Force Safe Mode (Extraction).${RESET}"
    echo "       Forces extraction of the video track to disk before converting."
    echo "       This is the robust fallback method usually triggered automatically on error,"
    echo "       but you can force it manually here for known problematic files."
    echo ""
    echo -e "  ${BOLD}-delete${RESET} [Convert, Batch]"
    echo -e "       ${YELLOW}Auto-Delete Mode.${RESET}"
    echo "       Automatically deletes the backup (Original Source) file immediately"
    echo "       after a successful conversion and verification."
    echo "       Use this for large batches where you don't have disk space to store backups."
    echo ""
    echo -e "  ${BOLD}-debug${RESET} [Global]"
    echo -e "       ${YELLOW}Debug Mode.${RESET}"
    echo "       Generates a 'dovi_convert_debug.log' file in the current directory"
    echo "       containing full ffmpeg/dovi_tool output. Essential for troubleshooting."
    echo ""
    echo -e "  ${BOLD}-y${RESET}     [Batch, Cleanup]"
    echo -e "       ${YELLOW}Auto-Yes Mode.${RESET}"
    echo "       Automatically answers 'Yes' to confirmation prompts (Batch Start / Cleanup)."
    echo "       Does NOT override safety decisions (like Safe Mode fallback)."
}

# --- Cleanup Logic (Soft Stop Handler) ---
cleanup_and_exit() {
    local exit_code=${1:-1}

    stop_spinner
    printf "\e[?25h" # SAFETY: Ensure cursor is visible if user hits Ctrl+C

    # Cleanup temp files
    if [[ -n "$raw_hevc" && -f "$raw_hevc" ]]; then rm -f "$raw_hevc"; fi
    if [[ -n "$conv_hevc" && -f "$conv_hevc" ]]; then rm -f "$conv_hevc"; fi
    if [[ -n "$temp_mkv" && -f "$temp_mkv" ]]; then rm -f "$temp_mkv"; fi
    
    # Analyze/Inspect Temp Files
    rm -f inspect_*.rpu inspect_*.json probe_*.hevc probe_*.rpu

    # Cleanup Log (Conditional)
    if [[ -n "$cmd_log" && -f "$cmd_log" && "$DEBUG_MODE" == false ]]; then
        rm -f "$cmd_log"
    fi

    # Handle User Interrupt (Ctrl+C)
    if [[ $exit_code -eq 130 ]]; then
        echo -e "\n${YELLOW}[!] Process Interrupted by User.${RESET}"
        echo -e "${YELLOW}[!] Cleaning up incomplete files... Done.${RESET}"
        if [[ "$BATCH_RUNNING" == true ]] || [[ -n "$backup_mkv" && -f "$backup_mkv" ]]; then
             echo -e "${GREEN}[✓] Original Source file is safe and untouched.${RESET}"
        fi
        ABORT_REQUESTED=true

        if [[ "$BATCH_RUNNING" == true ]]; then return 130; else echo "Exiting."; exit 130; fi
    fi

    if [[ "$BATCH_RUNNING" == true ]]; then return $exit_code; fi
    exit $exit_code
}
trap 'cleanup_and_exit 130' SIGINT SIGTERM

# --- Analysis Logic ---
# --- Analysis Logic ---
# Part 1: Identity / Metadata Extraction (Fast)
get_video_details() {
    local file="$1"
    
    VIDEO_TRACK_ID=""; VIDEO_DELAY="0"; VIDEO_LANG=""; VIDEO_NAME="";
    MI_INFO_STRING="" # Raw MediaInfo string for decision making

    if [[ ! -f "$file" ]]; then
       MI_INFO_STRING="FILE_NOT_FOUND"
       return
    fi


    # 1. Get Track ID & Properties
    local mkv_json
    mkv_json=$(mkvmerge -J "$file")
    VIDEO_TRACK_ID=$(echo "$mkv_json" | jq -r '.tracks[] | select(.type=="video") | .id' | head -n 1)

    if [[ -z "$VIDEO_TRACK_ID" ]]; then
        MI_INFO_STRING="NO_TRACK"
        return
    fi

    VIDEO_DELAY=$(echo "$mkv_json" | jq -r ".tracks[] | select(.id==$VIDEO_TRACK_ID) | .properties.minimum_timestamp // 0")
    VIDEO_LANG=$(echo "$mkv_json" | jq -r ".tracks[] | select(.id==$VIDEO_TRACK_ID) | .properties.language // \"und\"")
    VIDEO_NAME=$(echo "$mkv_json" | jq -r ".tracks[] | select(.id==$VIDEO_TRACK_ID) | .properties.track_name // empty")

    # 2. Get Dolby Profile
    local mi_json
    mi_json=$(mediainfo --Output=JSON "$file")

    MI_INFO_STRING=$(echo "$mi_json" | jq -r '.media.track[] | select(.["@type"]=="Video") | "\(.HDR_Format) \(.HDR_Format_Profile) \(.CodecID)"' | tr '\n' ' ')
}

# Part 2: Policy / Decision Making (Can start Deep Scan)
determine_action() {
    local file="$1"
    # Requires get_video_details to have run first
    
    DOVI_STATUS=""; ACTION=""

    if [[ "$MI_INFO_STRING" == "FILE_NOT_FOUND" ]]; then
        DOVI_STATUS="${RED}File not found${RESET}"; ACTION="ERROR"; return
    fi

    if [[ "$MI_INFO_STRING" == "NO_TRACK" ]]; then
        DOVI_STATUS="${RED}No Video Track${RESET}"; ACTION="SKIP"; return
    fi

    # 3. Decision Matrix
    if [[ "$MI_INFO_STRING" == *"dvhe.07"* ]] || [[ "$MI_INFO_STRING" == *"Profile 7"* ]]; then
        # PROFILE 7 DETECTED
        
        # DEEP SCAN (Always runs now, -quick removed)
        check_fel_complexity "$file"
        
        if [ "$FEL_VERDICT" == "COMPLEX" ]; then
            DOVI_STATUS="${RED}DV Profile 7 FEL (Complex)${RESET}"
            if [ "$FORCE_MODE" = true ]; then
                ACTION="CONVERT (FORCED)"
            else
                ACTION="SKIP (Complex FEL)"
            fi
        elif [ "$FEL_VERDICT" == "SAFE" ]; then
            DOVI_STATUS="${GREEN}DV Profile 7 FEL (Simple)${RESET}"
            ACTION="CONVERT"
        else
            DOVI_STATUS="${YELLOW}DV Profile 7 (Check Failed)${RESET}"
            ACTION="MANUAL CHECK"
        fi

    elif [[ "$MI_INFO_STRING" == *"dvhe.08"* ]] || [[ "$MI_INFO_STRING" == *"Profile 8"* ]]; then
        DOVI_STATUS="${CYAN}DV Profile 8.1${RESET}"; ACTION="IGNORE"
    elif [[ "$MI_INFO_STRING" == *"dvhe.05"* ]] || [[ "$MI_INFO_STRING" == *"Profile 5"* ]]; then
        DOVI_STATUS="${YELLOW}DV Profile 5 (Stream)${RESET}"; ACTION="IGNORE"
    elif [[ "$MI_INFO_STRING" == *"Dolby Vision"* ]]; then
        DOVI_STATUS="${RED}DV Unknown Profile${RESET}"; ACTION="CONVERT"
    else
        # Granular Detection
        if [[ "$MI_INFO_STRING" == *"2094"* ]]; then
            DOVI_STATUS="${CYAN}HDR10+${RESET}"
        elif [[ "$MI_INFO_STRING" == *"HLG"* ]] || [[ "$MI_INFO_STRING" == *"Hybrid Log Gamma"* ]]; then
            DOVI_STATUS="${CYAN}HLG${RESET}"
        elif [[ "$MI_INFO_STRING" == *"2086"* ]] || [[ "$MI_INFO_STRING" == *"HDR10"* ]]; then
            DOVI_STATUS="${CYAN}HDR10${RESET}"
        else
            DOVI_STATUS="${CYAN}SDR${RESET}"
        fi
        ACTION="IGNORE"
    fi
}

# Compatibility Wrapper (Legacy Analysis)
analyze_file() {
    local file="$1"
    get_video_details "$file"
    determine_action "$file"
}

# Command Wrapper
run_logged() {
    local cmd_log=""
    if [[ "$DEBUG_MODE" == true ]]; then
        cmd_log="dovi_convert_debug.log"
        echo "--- Command: $* ---" >> "$cmd_log"
    else
        cmd_log=$(mktemp)
    fi

    "$@" > "$cmd_log" 2>&1
    local status=$?

    if [[ $status -ne 0 ]]; then
        if [[ $status -eq 130 ]]; then
            if [[ "$DEBUG_MODE" == false ]]; then rm -f "$cmd_log"; fi
            return 130
        fi

        echo -e "${RED}Command Failed. Output:${RESET}"
        cat "$cmd_log"

        if [[ "$DEBUG_MODE" == false ]]; then rm -f "$cmd_log"; fi
        return $status
    fi

    if [[ "$DEBUG_MODE" == false ]]; then rm -f "$cmd_log"; fi
    return 0
}

# --- Conversion Method: Standard (Pipe) ---
convert_turbo() {
    local input="$1"
    local output="$2"
    local status=0

    # Initialize log file based on mode
    if [[ "$DEBUG_MODE" == true ]]; then
        cmd_log="dovi_convert_debug.log"
        echo "--- Standard Pipe Start: $input ---" >> "$cmd_log"
    else
        cmd_log=$(mktemp)
    fi

    # UI: Uniform Spinner
    start_spinner "[1/3] Converting... "

    # Unified Pipe Logic: Logs always captured to target log file
    set -o pipefail
    (ffmpeg -y -v error -i "$input" -c:v copy -bsf:v hevc_mp4toannexb -f hevc - 2>> "$cmd_log" \
    | dovi_tool -m 2 convert --discard - -o "$output" >> "$cmd_log" 2>&1)
    status=$?
    set +o pipefail

    stop_spinner

    # Success Case
    if [[ $status -eq 0 ]]; then
        printf "\r\e[K[1/3] Converting... Done.\n"
        if [[ "$DEBUG_MODE" == false ]]; then rm -f "$cmd_log"; fi
        return 0
    fi

    # --- ERROR HANDLING ---

    # 1. Check for User Abort (Ctrl+C)
    if [[ $status -eq 130 ]] || [[ "$ABORT_REQUESTED" == true ]]; then
          rm -f "$output"
          if [[ "$DEBUG_MODE" == false ]]; then rm -f "$cmd_log"; fi
          return 130
    fi

    rm -f "$output"

    # 2. Smart Analysis (Grepping the active log file)
    if grep -q -E "No space left on device|Permission denied|Read-only file system" "$cmd_log"; then
        echo "CRITICAL" > "$cmd_log.status"
        cat "$cmd_log" # Print error to user
        if [[ "$DEBUG_MODE" == false ]]; then rm -f "$cmd_log"; fi
        return 1
    fi

    if grep -q -E "Invalid data|Invalid NAL unit|conversion failed|Error splitting" "$cmd_log"; then
        echo "STREAM_ERROR" > "$cmd_log.status"
        if [[ "$DEBUG_MODE" == false ]]; then rm -f "$cmd_log"; fi
        return 1
    fi

    echo "UNKNOWN" > "$cmd_log.status"
    cat "$cmd_log" # Print unknown error to user
    if [[ "$DEBUG_MODE" == false ]]; then rm -f "$cmd_log"; fi
    return 1
}

# --- Conversion Method: Safe (Extraction) ---
convert_legacy() {
    local input="$1"
    local output="$2"
    local raw_temp="${input%.*}.raw.hevc"
    raw_hevc="$raw_temp"

    # Extraction Step
    start_spinner "[1/3] Extracting... "
    run_logged mkvextract "$input" tracks "$VIDEO_TRACK_ID:$raw_temp"
    local res=$?
    stop_spinner

    if [[ $res -eq 0 ]]; then printf "\r\e[K[1/3] Extracting... Done.\n"; fi

    if [[ $res -eq 130 ]] || [[ "$ABORT_REQUESTED" == true ]]; then return 130; fi
    if [[ $res -ne 0 ]]; then return 1; fi

    # Conversion Step
    start_spinner "[1/3] Converting... "
    run_logged dovi_tool -m 2 convert --discard "$raw_temp" -o "$output"
    local status=$?
    stop_spinner

    if [[ $status -eq 0 ]]; then printf "\r\e[K[1/3] Converting... Done.\n"; fi

    rm -f "$raw_temp"
    if [[ $status -eq 130 ]]; then return 130; fi
    return $status
}

# --- Main Conversion Logic ---
cmd_convert() {
    local file="$1"
    local mode="$2"

    if [[ ! -f "$file" ]]; then echo "File not found: $file"; return 1; fi
    analyze_file "$file"

    # Safety Check: Complex FEL
    if [[ "$FEL_VERDICT" == "COMPLEX" ]]; then
        if [[ "$FORCE_MODE" == true ]]; then
             echo -e "${RED}Complex FEL detected. Force Mode enabled. Proceeding...${RESET}"
        else
             if [[ "$mode" == "auto" ]]; then return 2; fi # Quiet skip for batch
             echo -e "${RED}Error: Complex FEL detected (not safe to convert. Use -force to override).${RESET}"
             return 1
        fi
    fi

    # Safety Check: Not Profile 7 (IGNORE) or Generic SKIP (e.g. No Video Track)
    # Note: SKIP (Complex FEL) is already handled above due to FEL_VERDICT check.
    # We check for generic SKIP (e.g. No Video Track) or IGNORE.
    if [[ "$ACTION" == "IGNORE" || "$ACTION" == "SKIP" ]]; then
        if [[ "$mode" == "auto" ]]; then return 2; fi
        echo -e "${RED}Error: Input file is not a Dolby Vision Profile 7 file.${RESET}"
        return 1
    fi

    echo -e "${BOLD}Processing:${RESET} $file"
    base_name="${file%.*}"
    conv_hevc="${base_name}.p81.hevc"
    temp_mkv="${base_name}.p81.mkv"
    local backup_mkv="${file}.bak.dovi_convert"

    if [[ -f "$backup_mkv" ]]; then
        echo -e "${RED}Skipping: Backup file already exists.${RESET}"
        return 1
    fi

    # Initialize Metrics
    START_TIME=$SECONDS
    ORIG_SIZE=$(get_file_size "$file")

    # Step 0: FPS Safety
    local fps_orig=$(mediainfo --Output="Video;%FrameRate%" "$file")
    if [[ -z "$fps_orig" ]]; then echo -e "${RED}Error: Could not detect Frame Rate.${RESET}"; return 1; fi

    # Step 1 & 2: Extraction & Conversion
    local conversion_done=false

    if [[ "$SAFE_MODE" == true ]]; then
        if ! convert_legacy "$file" "$conv_hevc"; then
            if [[ "$ABORT_REQUESTED" == true ]]; then return 130; fi
            echo "${RED}Safe Mode Failed.${RESET}"; cleanup_and_exit 1; return 1
        fi
        conversion_done=true
    else
        convert_turbo "$file" "$conv_hevc"
        local turbo_res=$?

        if [[ $turbo_res -eq 0 ]]; then
            conversion_done=true
        elif [[ $turbo_res -eq 130 ]] || [[ "$ABORT_REQUESTED" == true ]]; then
            return 130
        else
            echo "${RED}Standard Mode Failed.${RESET}"

            local fail_reason=$(cat "$cmd_log.status" 2>/dev/null)
            rm -f "$cmd_log.status"

            if [[ "$fail_reason" == "CRITICAL" ]]; then
                 echo -e "${RED}CRITICAL ERROR: Disk Full or Permission Denied.${RESET}"
                 cleanup_and_exit 1; exit 1
            elif [[ "$fail_reason" == "STREAM_ERROR" ]]; then
                 echo -e "${YELLOW}Reason: Stream/Timestamp Error (Likely Seamless Branching).${RESET}"
            fi

            if [[ "$BATCH_RUNNING" == true ]]; then
                echo -e "${YELLOW}Batch Mode: Skipping file. Retry manually with -safe.${RESET}"
                return 1
            else
                echo -e "${YELLOW}Suggestion: This file may require Safe Mode (Disk Extraction).${RESET}"
                printf "Retry with Safe Mode? (Y/n) "
                read -r REPLY
                if [[ "$REPLY" =~ ^[Nn]$ ]]; then cleanup_and_exit 1; return 1; fi

                echo -n "[Retry] "
                if ! convert_legacy "$file" "$conv_hevc"; then
                    if [[ "$ABORT_REQUESTED" == true ]]; then return 130; fi
                    echo "${RED}Safe Mode also failed.${RESET}"; cleanup_and_exit 1; return 1
                fi
                conversion_done=true
            fi
        fi
    fi

    if [[ "$conversion_done" == false ]]; then return 1; fi

    # Step 3: Muxing
    local mux_args=("-o" "$temp_mkv")
    if [[ "$VIDEO_DELAY" != "0" ]]; then mux_args+=("--sync" "0:$VIDEO_DELAY"); fi
    mux_args+=("--default-duration" "0:${fps_orig}fps" "--language" "0:$VIDEO_LANG")
    if [[ -n "$VIDEO_NAME" ]]; then mux_args+=("--track-name" "0:$VIDEO_NAME"); fi
    mux_args+=("$conv_hevc" "--no-video" "$file")

    start_spinner "[2/3] Muxing (Cloning Metadata + ${fps_orig}fps)... "
    run_logged mkvmerge "${mux_args[@]}"
    local mux_res=$?
    stop_spinner

    if [[ $mux_res -eq 130 ]] || [[ "$ABORT_REQUESTED" == true ]]; then return 130; fi
    if [[ $mux_res -ne 0 ]]; then
        echo "${RED}Mux Failed.${RESET}"; cleanup_and_exit 1; return 1
    fi
    printf "\r\e[K[2/3] Muxing (Cloning Metadata + ${fps_orig}fps)... Done.\n"

    # Step 4: Verification
    start_spinner "[3/3] Verifying... "
    local frames_orig=$(mediainfo --Output="Video;%FrameCount%" "$file")
    local frames_new=$(mediainfo --Output="Video;%FrameCount%" "$temp_mkv")
    stop_spinner

    if [[ -n "$frames_orig" ]] && [[ "$frames_orig" != "$frames_new" ]]; then
          printf "\r\e[K[3/3] Verifying... ${RED}FAIL: Frame mismatch!${RESET} ($frames_orig vs $frames_new)\n"
          cleanup_and_exit 1; return 1
    fi
    printf "\r\e[K[3/3] Verifying... ${GREEN}Success!${RESET}\n"

    # Print Metrics
    print_metrics "$temp_mkv" "$frames_new"

    # Step 5: Atomic Swap
    mv "$file" "$backup_mkv"
    mv "$temp_mkv" "$file"

    if [[ "$DELETE_BACKUP" == true ]]; then
        rm "$backup_mkv"
        echo -e "${YELLOW}Original Source deleted (-delete active).${RESET}"
    else
        echo -e "Original Source saved as: ${CYAN}${backup_mkv}${RESET}"
    fi

    rm -f "$conv_hevc"
    return 0
}

# --- Cleanup Logic (Smart Disk Sweep) ---
cmd_cleanup() {
    local recursive="$1"
    local find_cmd=(find .)

    if [[ "$recursive" == "true" ]]; then
        echo -e "${BOLD}Scanning for .bak.dovi_convert files (Recursive)...${RESET}"
    else
        echo -e "${BOLD}Scanning for .bak.dovi_convert files (Current Directory)...${RESET}"
        find_cmd+=(-maxdepth 1)
    fi

    find_cmd+=(-name "*.mkv.bak.dovi_convert" -print0)

    local files=()
    local total_size=0
    while IFS= read -r -d '' f; do
        local parent_file="${f%.bak.dovi_convert}"
        if [[ -f "$parent_file" ]]; then
            files+=("$f")
            local size=$(get_file_size "$f")
            total_size=$((total_size + size))
        else
            echo -e "${YELLOW}Skipping Orphan Backup:${RESET} $(basename "$f")"
        fi
    done < <("${find_cmd[@]}")

    if [[ ${#files[@]} -eq 0 ]]; then echo "No valid backup files found."; return 0; fi

    echo -e "\n${BOLD}Files found:${RESET}"
    for f in "${files[@]}"; do
        echo " - $f"
    done

    local size_gb=$(human_size_gb $total_size)
    echo -e "\nFound ${BOLD}${#files[@]} valid backups${RESET} utilizing ${BOLD}${size_gb}${RESET}."

    if [[ "$AUTO_YES" == true ]]; then
        echo -e "${YELLOW}Auto-Yes (-y) active. Deleting files...${RESET}"
        REPLY="y"
    else
        printf "Delete them? (y/N) "
        read -r REPLY
    fi

    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        for f in "${files[@]}"; do rm "$f"; echo "Deleted: $(basename "$f")"; done
    else
        echo "Cancelled."
    fi
}

# --- Batch Processing Logic ---
cmd_batch() {
    local max_depth="${1:-1}"
    BATCH_RUNNING=true
    local conversion_queue=(); local success_list=(); local fail_list=()
    local ignored_count=0; local skipped_count=0; local complex_count=0
    local simple_count=0; local forced_count=0
    local total_batch_size=0

    echo -e "${BOLD}Scanning for Profile 7 files (Depth: $max_depth)...${RESET}"
    while IFS= read -r -d '' file; do
        analyze_file "$file"
        if [[ "$ACTION" == CONVERT* ]]; then
            conversion_queue+=("$file")
            if [[ "$ACTION" == *"FORCED"* ]]; then
                ((forced_count++))
            else
                ((simple_count++))
            fi
            local f_size=$(get_file_size "$file")
            total_batch_size=$((total_batch_size + f_size))
        elif [[ "$ACTION" == "IGNORE" ]]; then
            ((ignored_count++))
        elif [[ "$FEL_VERDICT" == "COMPLEX" ]]; then
             # Separately track Complex FEL skips
            ((complex_count++))
        else
            # SKIP (Invalid/No Track/etc)
            ((skipped_count++))
        fi
    done < <(find . -maxdepth "$max_depth" -name "*.mkv" -print0 | sort -z)

    if [[ ${#conversion_queue[@]} -eq 0 && $complex_count -eq 0 ]]; then 
         echo "No Profile 7 files found (Ignored: $ignored_count)."
         return 0
    fi

    # --- Interactive Overview ---
    local queue_count=${#conversion_queue[@]}
    local total_size_gb=$(human_size_gb $total_batch_size)

    echo -e "\n${BOLD}Batch Overview:${RESET}"
    if [[ $simple_count -gt 0 ]]; then
        echo -e "  Convert:        ${GREEN}$simple_count${RESET}   (Simple FEL / MEL)"
    fi
    if [[ $forced_count -gt 0 ]]; then
        echo -e "  Convert:        ${YELLOW}$forced_count${RESET}   (Complex FEL - Forced)"
    fi
    if [[ $complex_count -gt 0 ]]; then
        echo -e "  Skip:           ${RED}$complex_count${RESET}   (Complex FEL)"
    fi
    echo -e "  Queue Size:     ${CYAN}$total_size_gb${RESET}"

    if [[ "$AUTO_YES" == true ]]; then
        echo -e "${YELLOW}Auto-Yes (-y) active. Starting conversion immediately...${RESET}"
        sleep 2
    else
        # If queue is empty but we found skipped Complex FEL, just exit nicely.
        if [[ $queue_count -eq 0 ]]; then
             echo -e "\nNo files eligible for conversion."
             echo -e "Ignored: $ignored_count (Not P7), Complex FEL: $complex_count (Unsafe), Skipped: $skipped_count (Invalid)."
             return 0
        fi

        printf "\nShow file list? (y/N) "
        read -r REPLY
        if [[ "$REPLY" =~ ^[Yy]$ ]]; then
            echo -e "\n${BOLD}Conversion Queue:${RESET}"
            for f in "${conversion_queue[@]}"; do echo " - $f"; done
        fi

        printf "\nProceed with conversion? (Y/n) "
        read -r REPLY
        if [[ "$REPLY" =~ ^[Nn]$ ]]; then
            echo "Batch cancelled."
            return 0
        fi
    fi

    echo ""
    echo "==================================================="
    echo "BATCH PROCESSING STARTED"
    echo "==================================================="

    local current_idx=1
    local success_simple_count=0; local success_forced_count=0

    for file in "${conversion_queue[@]}"; do
        if [[ "$ABORT_REQUESTED" == true ]]; then break; fi

        echo "---------------------------------------------------"
        echo -e "${BOLD}[$current_idx/$queue_count]${RESET} Processing: $(basename "$file")"
        cmd_convert "$file" "auto"
        local res=$?

        if [[ $res -eq 130 ]] || [[ "$ABORT_REQUESTED" == true ]]; then
            break # Soft Stop requested by User
        elif [[ $res -eq 0 ]]; then
            success_list+=("$(basename "$file")")
            if [[ "$FEL_VERDICT" == "COMPLEX" ]]; then
                ((success_forced_count++))
            else
                ((success_simple_count++))
            fi
        elif [[ $res -eq 2 ]]; then
            # Should not happen since we filtered queue, but if it does (e.g. file vanished)
            ((skipped_count++))
        else
            fail_list+=("$(basename "$file")")
        fi
        ((current_idx++))
    done
    BATCH_RUNNING=false

    echo -e "\n==================================================="
    if [[ "$ABORT_REQUESTED" == true ]]; then
        echo -e "           ${YELLOW}${BOLD}BATCH ABORTED BY USER${RESET}"
    else
        echo -e "           ${BOLD}BATCH PROCESSING COMPLETE${RESET}"
    fi
    echo "==================================================="
    echo "Processed:"
    if [[ $success_simple_count -gt 0 ]]; then
        echo -e "  - Converted:   ${GREEN}$success_simple_count${RESET}   (Simple FEL / MEL)"
    fi
    if [[ $success_forced_count -gt 0 ]]; then
        echo -e "  - Converted:   ${YELLOW}$success_forced_count${RESET}   (Complex FEL - Forced)"
    fi
    if [[ ${#success_list[@]} -eq 0 ]]; then
         echo -e "  - Converted:   0"
    fi
    echo -e "  - Failed:      ${RED}${#fail_list[@]}${RESET}"
    echo ""
    echo "Not Processed:"
    echo -e "  - Ignored:     ${CYAN}$ignored_count${RESET}   (Not Profile 7)"
    echo -e "  - Complex FEL: ${RED}$complex_count${RESET}   (Unsafe / Skipped)"
    echo -e "  - Invalid:     ${YELLOW}$skipped_count${RESET}   (Corrupt / No Track)"

    if [[ ${#fail_list[@]} -gt 0 ]]; then
        echo "---------------------------------------------------"
        echo -e "${YELLOW}Failed Files (Likely Seamless Branching / Stream Issues):${RESET}"
        for f in "${fail_list[@]}"; do echo " - $f"; done
        echo ""
        echo -e "${BOLD}Suggestion:${RESET} Try converting these specific files using Safe Mode:"
        echo -e "  dovi_convert -convert \"filename.mkv\" -safe"
    fi
    echo "==================================================="
    send_notification "dovi_convert" "Batch Complete."
}

# ------------------------------------------------------------------------------
# INSPECT (L1 ANALYSIS)
# ------------------------------------------------------------------------------
cmd_inspect() {
    local file="$1"

    if [ ! -f "$file" ]; then
        echo -e "${RED}Error: File '$file' not found.${RESET}"
        exit 1
    fi

    # 1. Basic Validation
    # Optimization: Call get_video_details only (Part 1).
    get_video_details "$file" # populate globals (VIDEO_TRACK_ID, MI_INFO_STRING)
    
    if [[ "$MI_INFO_STRING" != *"dvhe.07"* ]] && [[ "$MI_INFO_STRING" != *"Profile 7"* ]]; then
        echo -e "${RED}Error: File is not Dolby Vision Profile 7.${RESET}"
        echo -e "Detected: $DOVI_STATUS (Info: $MI_INFO_STRING)"
        exit 1
    fi

    echo ""
    echo "==================================================="
    echo -e "${BOLD}FULL RPU STRUCTURE INSPECTION${RESET}"
    echo "==================================================="
    echo -e "File:       ${BOLD}$(basename -- "$file")${RESET}"
    echo -e "Format:     DV Profile 7 (Scanning...)"
    echo "---------------------------------------------------"

    local temp_rpu="inspect_$(date +%s)_$$.rpu"
    local use_safe_mode=$SAFE_MODE

    # 2. Extract Full RPU
    # Loop to allow Fallback to Safe Mode
    while true; do
        if [ "$use_safe_mode" = false ]; then
            # Method A: Standard Pipe (Fast)
            start_spinner "Extracting RPU (Standard Pipe)... "
            # Set pipefail to catch ffmpeg errors in the pipe chain
            set -o pipefail
            (ffmpeg -v error -i "$file" -map 0:$VIDEO_TRACK_ID -c:v copy -bsf:v hevc_mp4toannexb -f hevc - 2>/dev/null \
            | dovi_tool extract-rpu - -o "$temp_rpu" >/dev/null 2>&1)
            local status=$?
            set +o pipefail
            stop_spinner

            if [ $status -eq 0 ] && [ -s "$temp_rpu" ]; then
                printf "\r\e[KExtracting RPU... Done.\n"
                break # Success
            else
                # Pipe Failed
                printf "\r\e[KExtracting RPU... ${RED}Failed.${RESET}\n"
                rm -f "$temp_rpu"
                
                # Check for Auto-Yes or Interactive
                if [ "$AUTO_YES" = true ]; then
                     echo -e "${YELLOW}Standard inspection failed. Auto-Yes enabled. Retrying with Safe Mode.${RESET}"
                     use_safe_mode=true
                     continue
                else
                     echo -e "${YELLOW}Notice: Standard inspection failed (likely Seamless Branching/Packet Issues).${RESET}"
                     read -p "Retry using Safe Mode (Extraction to Disk)? [Y/n] " -n 1 -r
                     echo ""
                     if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
                         use_safe_mode=true
                         continue
                     else
                         echo -e "${RED}Aborted by user.${RESET}"
                         exit 1
                     fi
                fi
            fi
        else
            # Method B: Safe Mode (Extraction)
            local raw_temp="inspect_temp_$(date +%s)_$$.hevc"
            start_spinner "Extracting Track (Safe Mode)... "
            mkvextract "$file" tracks "$VIDEO_TRACK_ID:$raw_temp" >/dev/null 2>&1
            local res=$?
            stop_spinner
            
            if [ $res -ne 0 ]; then
                printf "\r\e[KExtracting Track... ${RED}Failed.${RESET}\n"
                rm -f "$raw_temp"
                exit 1
            fi
            printf "\r\e[KExtracting Track... Done.\n"

            start_spinner "Extracting RPU (From Element)... "
            dovi_tool extract-rpu "$raw_temp" -o "$temp_rpu" >/dev/null 2>&1
            local status=$?
            stop_spinner
            
            rm -f "$raw_temp" # Clean up large HEVC file

            if [ $status -eq 0 ] && [ -s "$temp_rpu" ]; then
                printf "\r\e[KExtracting RPU... Done.\n"
                break
            else
                echo -e "${RED}Error: RPU extraction failed even in Safe Mode.${RESET}"
                rm -f "$temp_rpu"
                exit 1
            fi
        fi
    done

    # 3. Analyze L1 (Summary Mode)
    start_spinner "Analyzing L1 Metadata... "
    local analysis_output
    analysis_output=$(dovi_tool info -s -i "$temp_rpu" 2>&1)
    stop_spinner
    printf "\r\e[KAnalyzing L1 Metadata... Done.\n"

    rm -f "$temp_rpu"

    # 4. Parse Data
    local bl_peak
    # MediaInfo MasteringDisplay_Luminance format: "min: 0.0001 cd/m2, max: 1000 cd/m2"
    local raw_bl_peak
    raw_bl_peak=$(mediainfo --Output="Video;%MasteringDisplay_Luminance%" "$file" | grep -o "max: [0-9]*" | grep -o "[0-9]*")
    bl_peak="${raw_bl_peak:-1000}" # Default to 1000 if extraction fails

    local rpu_peak
    # Parse "RPU content light level (L1): MaxCLL: 254.98 nits"
    # We use awk to find the line containing "MaxCLL" and extract the number.
    local raw_rpu_peak
    raw_rpu_peak=$(echo "$analysis_output" | grep "RPU content light level (L1)" | grep -o "MaxCLL: [0-9.]*" | grep -o "[0-9.]*")
    
    # Round to integer using printf/bash arithmetic
    if [[ -n "$raw_rpu_peak" ]]; then
        rpu_peak=$(printf "%.0f" "$raw_rpu_peak")
    else
        rpu_peak=0
    fi

    local diff=$(( rpu_peak - bl_peak ))
    local verdict=""
    local advisory=""

    # Tolerance of 50 nits
    if [ "$diff" -gt 50 ]; then
        verdict="${RED}COMPLEX FEL (Active Brightness Expansion)${RESET}"
        advisory="${BOLD}ADVISORY:${RESET}\nBrightness data exists in the Enhancement Layer.\nConversion will result in quality loss and incorrect tone mapping.\n\nUse -force to convert anyway."
    else
        verdict="${GREEN}SIMPLE / CONTAINED${RESET}"
        advisory="${BOLD}ADVISORY:${RESET}\nRPU matches Base Layer brightness.\nSafe to convert."
    fi

    echo "Base Layer Peak:      ${bl_peak} nits"
    echo "RPU L1 Peak (Max):    ${rpu_peak} nits"
    echo "Difference:           ${diff} nits"
    echo "---------------------------------------------------"
    echo -e "${BOLD}VERDICT:${RESET}    ${verdict}"
    echo "---------------------------------------------------"
    echo -e "$advisory"
    echo "==================================================="
    echo ""
}

# --- Reporting Commands ---
cmd_check_single() {
    local file="$1"; analyze_file "$file"; local delay_ms=$(echo "scale=0; $VIDEO_DELAY/1000000" | bc)
    
    if [[ "$MI_INFO_STRING" == "FILE_NOT_FOUND" ]]; then
       echo -e "${RED}Error: File '$file' not found.${RESET}"
       return
    fi
    
    local name=$(basename -- "$file")

    echo "---------------------------------------------------"
    echo -e "${BOLD}File:${RESET}   $name"
    echo -e "${BOLD}Status:${RESET} $DOVI_STATUS"
    echo -e "${BOLD}Action:${RESET} $ACTION"
    echo "---------------------------------------------------"
}

cmd_check_all() {
    local max_depth="${1:-1}"
    
    # 1. Build Header Message
    local scan_type="Deep Scan"
    
    local location="in current directory"
    if [[ "$max_depth" -gt 1 ]]; then location="recursively ($max_depth levels deep)"; fi
    
    echo -e "${CYAN}Running $scan_type $location...${RESET}"
    
    # 2. Print Table Header
    printf "%-50s %-27s %s\n" "Filename" "Format" "Action"
    echo "------------------------------------------------------------------------------------------------"
    
    # 3. Iterate
    while IFS= read -r -d '' file; do
        analyze_file "$file"
        local name="${file#./}"; 
        # Truncate filename (Strict 48 chars + '...')
        if [ ${#name} -gt 48 ]; then name="${name:0:48}..."; fi
        printf "%-50s %-36b %b\n" "$name" "${DOVI_STATUS}" "${ACTION}"
    done < <(find . -maxdepth "$max_depth" -name "*.mkv" -print0 | sort -z)
}

# ------------------------------------------------------------------------------
# ARGUMENT PARSER (TWO-PASS)
# ------------------------------------------------------------------------------

# Pass 1: Global Flag Harvesting
ARGS=()
for arg in "$@"; do
    case "$arg" in
        -force) FORCE_MODE=true ;;
        -safe)  SAFE_MODE=true ;;
        -y)     AUTO_YES=true ;;
        -debug) DEBUG_MODE=true ;;
        -delete) DELETE_BACKUP=true ;;
        *) ARGS+=("$arg") ;; # Keep non-global args
    esac
done

# Reset positional parameters to the remaining args
set -- "${ARGS[@]}"

# Pre-flight checks
if ! command -v dovi_tool &> /dev/null; then
    echo -e "${RED}Error: dovi_tool not found.${RESET}"
    exit 1
fi

# Pass 2: Action Dispatch
if [ $# -eq 0 ]; then
    print_usage
    exit 0
fi

COMMAND="$1"
shift

case "$COMMAND" in
    -check)
        if [[ "$1" == "-r" ]]; then
            shift
            # If next arg is a number, use it as depth. Otherwise default to 5.
            depth="5"
            if [[ "$1" =~ ^[0-9]+$ ]]; then
                depth="$1"
            fi
            cmd_check_all "$depth"
        elif [ -z "$1" ]; then 
            # Check all in current dir if no file
            cmd_check_all 1
        else
            cmd_check_single "$1"
        fi
        ;;
    -convert)
        # Note: Previous convert logic expected $2 to be file. 
        # Here we already shifted, so $1 is file.
        FILE="$1"
        if [ -z "$FILE" ]; then echo "Usage: -convert [file]"; exit 1; fi
        cmd_convert "$FILE" "manual"
        ;;
    -inspect|--inspect)
        FILE="$1"
        if [ -z "$FILE" ]; then echo "Usage: -inspect [file]"; exit 1; fi
        cmd_inspect "$FILE"
        ;;

    -batch)
        DEPTH="$1"
        cmd_batch "${DEPTH:-1}"
        ;;
    -cleanup)
        # Handle optional -r flag if it wasn't stripped? 
        # Actually -r is specific to cleanup, not global.
        if [[ "$1" == "-r" ]]; then
            cmd_cleanup "true"
        else
            cmd_cleanup "false"
        fi
        ;;
    -help|--help)
        if command -v less &> /dev/null && [ -t 1 ]; then
            print_help | less -R
        else
            print_help
        fi
        ;;
    *)
        print_log "${RED}Unknown command: $COMMAND${RESET}"
        print_usage
        exit 1
        ;;
esac
