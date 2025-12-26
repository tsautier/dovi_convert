#!/usr/bin/env bash
# =============================================================================
# dovi_convert - Dolby Vision Profile 7 -> 8.1 Converter (v6.6.1)
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
INCLUDE_SIMPLE=false    # Toggled by -include-simple

# App Data
VERSION="6.6.1"
REPO_URL="https://api.github.com/repos/cryptochrome/dovi_convert/releases/latest"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/dovi_convert"
UPDATE_FILE="$CACHE_DIR/latest_version"

# Global Variables for Metrics
START_TIME=0
ORIG_SIZE=0

# --- Pre-Flight: Safety Check ---
if ! pwd > /dev/null 2>&1; then
    echo -e "${RED}Error: Ghost directory detected.${RESET} Please 'cd .' or restart terminal."
    exit 1
fi

# --- Pre-Flight: Dependency Check & Auto-Install ---

# Package name mapping (command -> package name per manager)
# Format: "command:brew:apt:dnf:pacman"
DEP_MAP=(
    "mkvmerge:mkvtoolnix:mkvtoolnix:mkvtoolnix:mkvtoolnix"
    "mkvextract:mkvtoolnix:mkvtoolnix:mkvtoolnix:mkvtoolnix"
    "dovi_tool:dovi_tool:dovi_tool:dovi_tool:dovi_tool"
    "mediainfo:mediainfo:mediainfo:mediainfo:mediainfo"
    "jq:jq:jq:jq:jq"
    "bc:bc:bc:bc:bc"
    "ffmpeg:ffmpeg:ffmpeg:ffmpeg:ffmpeg"
    "curl:curl:curl:curl:curl"
)

get_pkg_name() {
    local cmd="$1" pm="$2"
    for entry in "${DEP_MAP[@]}"; do
        IFS=':' read -r e_cmd e_brew e_apt e_dnf e_pacman <<< "$entry"
        if [[ "$e_cmd" == "$cmd" ]]; then
            case "$pm" in
                brew) echo "$e_brew" ;;
                apt) echo "$e_apt" ;;
                dnf) echo "$e_dnf" ;;
                pacman) echo "$e_pacman" ;;
            esac
            return
        fi
    done
    echo "$cmd"  # Fallback to command name
}

check_pkg_available() {
    local pkg="$1" pm="$2"
    case "$pm" in
        brew) brew info "$pkg" &>/dev/null ;;
        apt) apt-cache show "$pkg" &>/dev/null ;;
        dnf) dnf info "$pkg" &>/dev/null 2>&1 ;;
        pacman) pacman -Si "$pkg" &>/dev/null 2>&1 ;;
    esac
}

install_dependencies() {
    local missing=("$@")
    local pm="" pm_install="" needs_sudo=false is_arch=false
    local has_brew_fallback=false
    local installed=() failed=() manual=()
    
    # Detect package manager (on Linux, prefer native over Homebrew)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS: Homebrew only
        if command -v brew &>/dev/null; then
            pm="brew"; pm_install="brew install"; needs_sudo=false
        else
            echo -e "${YELLOW}Homebrew is not installed.${RESET}"
            echo "It's the recommended way to install dependencies on macOS."
            echo ""
            echo "Install it from: https://brew.sh"
            echo ""
            echo "Then run dovi_convert again."
            exit 1
        fi
    elif command -v apt &>/dev/null; then
        pm="apt"; pm_install="sudo apt install -y"; needs_sudo=true
        if command -v brew &>/dev/null; then has_brew_fallback=true; fi
    elif command -v dnf &>/dev/null; then
        pm="dnf"; pm_install="sudo dnf install -y"; needs_sudo=true
        if command -v brew &>/dev/null; then has_brew_fallback=true; fi
    elif command -v pacman &>/dev/null; then
        pm="pacman"; pm_install="sudo pacman -S --noconfirm"; needs_sudo=true; is_arch=true
        if command -v brew &>/dev/null; then has_brew_fallback=true; fi
    elif command -v brew &>/dev/null; then
        # Linux with only Homebrew (no native PM)
        pm="brew"; pm_install="brew install"; needs_sudo=false
    else
        echo -e "${RED}Unsupported system.${RESET} Please install dependencies manually:"
        for dep in "${missing[@]}"; do echo "  - $dep"; done
        exit 1
    fi
    
    # Sudo warning
    if [[ "$needs_sudo" == true ]]; then
        echo ""
        echo -e "${YELLOW}Note: Installation requires administrator privileges.${RESET}"
        echo "You may be prompted for your password."
        echo ""
    fi
    
    local total=${#missing[@]}
    local idx=1
    
    # Track unique packages to avoid duplicate installs (mkvmerge & mkvextract = mkvtoolnix)
    local already_installed=()
    
    for cmd in "${missing[@]}"; do
        local pkg=$(get_pkg_name "$cmd" "$pm")
        local use_pm="$pm"
        local use_pm_install="$pm_install"
        
        # Skip if we already installed this package
        if [[ " ${already_installed[*]} " =~ " ${pkg} " ]]; then
            ((idx++))
            continue
        fi
        
        echo -n "[$idx/$total] Installing $cmd ($pkg)... "
        
        # Check if package is available in primary repos
        if ! check_pkg_available "$pkg" "$use_pm"; then
            # Not in native repos - try Homebrew fallback for dovi_tool on Linux
            if [[ "$cmd" == "dovi_tool" ]] && [[ "$has_brew_fallback" == true ]]; then
                local brew_pkg=$(get_pkg_name "$cmd" "brew")
                if check_pkg_available "$brew_pkg" "brew"; then
                    echo -n "(via Homebrew) "
                    use_pm="brew"
                    use_pm_install="brew install"
                    pkg="$brew_pkg"
                else
                    echo -e "${YELLOW}Not in repos.${RESET}"
                    manual+=("$cmd")
                    ((idx++))
                    continue
                fi
            else
                echo -e "${YELLOW}Not in repos.${RESET}"
                manual+=("$cmd")
                ((idx++))
                continue
            fi
        fi
        
        # Attempt install
        if $use_pm_install "$pkg" &>/dev/null; then
            echo -e "${GREEN}Done.${RESET}"
            installed+=("$cmd")
            already_installed+=("$pkg")
        else
            echo -e "${RED}Failed.${RESET}"
            failed+=("$cmd")
        fi
        ((idx++))
    done
    
    # Summary
    echo ""
    echo "---------------------------------------------------"
    echo -e "${BOLD}INSTALLATION SUMMARY${RESET}"
    echo "---------------------------------------------------"
    
    if [[ ${#installed[@]} -gt 0 ]]; then
        echo -e "Installed:    ${GREEN}${installed[*]}${RESET}"
    fi
    if [[ ${#failed[@]} -gt 0 ]]; then
        echo -e "Failed:       ${RED}${failed[*]}${RESET}"
    fi
    if [[ ${#manual[@]} -gt 0 ]]; then
        echo -e "Manual Setup: ${YELLOW}${manual[*]}${RESET}"
    fi
    
    # Manual install instructions
    if [[ ${#manual[@]} -gt 0 ]] || [[ ${#failed[@]} -gt 0 ]]; then
        echo ""
        local needs_manual=("${manual[@]}" "${failed[@]}")
        
        for dep in "${needs_manual[@]}"; do
            if [[ "$dep" == "dovi_tool" ]]; then
                echo "dovi_tool must be installed manually:"
                if [[ "$is_arch" == true ]]; then
                    echo "  AUR:    https://aur.archlinux.org/packages/dovi_tool-bin"
                fi
                echo "  GitHub: https://github.com/quietvoid/dovi_tool/releases"
            else
                echo "$dep must be installed manually using your package manager."
            fi
        done
        
        echo ""
        echo "Please install, then run dovi_convert again."
        echo "---------------------------------------------------"
        exit 1
    fi
    
    echo "---------------------------------------------------"
    echo -e "${GREEN}All dependencies installed successfully!${RESET}"
    echo ""
}

# Check for missing dependencies
MISSING_DEPS=()
for entry in "${DEP_MAP[@]}"; do
    cmd="${entry%%:*}"
    if ! command -v "$cmd" &>/dev/null; then
        # Avoid duplicate entries (mkvmerge and mkvextract are same package)
        if [[ ! " ${MISSING_DEPS[*]} " =~ " ${cmd} " ]]; then
            MISSING_DEPS+=("$cmd")
        fi
    fi
done

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
    echo -e "${RED}Missing dependencies:${RESET} ${MISSING_DEPS[*]}"
    echo ""
    printf "Would you like to install them automatically? (y/N) "
    read -r REPLY
    
    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        install_dependencies "${MISSING_DEPS[@]}"
    else
        echo ""
        echo "Please install the missing dependencies manually:"
        for dep in "${MISSING_DEPS[@]}"; do
            if [[ "$dep" == "dovi_tool" ]]; then
                echo "  - dovi_tool: https://github.com/quietvoid/dovi_tool/releases"
            else
                echo "  - $dep"
            fi
        done
        exit 1
    fi
fi

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

# --- Version Comparison Helper ---
version_gt() {
    # Returns 0 if $1 > $2 (First is greater than Second)
    local v1=${1#v}
    local v2=${2#v}
    
    if [[ "$v1" == "$v2" ]]; then return 1; fi
    
    local IFS=.
    local i v1_parts=($v1) v2_parts=($v2)
    
    for ((i=0; i<${#v1_parts[@]}; i++)); do
        if [[ -z ${v2_parts[i]} ]]; then return 0; fi # v1 longer = greater
        if (( ${v1_parts[i]} > ${v2_parts[i]} )); then return 0; fi
        if (( ${v1_parts[i]} < ${v2_parts[i]} )); then return 1; fi
    done
    
    # If we are here, v1 is prefix of v2 or equal. 
    # v1 cannot be greater.
    return 1
}

# --- Update Check Logic ---

# Background: Fetches latest tag from GitHub and saves to file (Zero Latency for user)
check_for_updates_background() {
    # Run in subshell, completely detached
    (
        mkdir -p "$CACHE_DIR"
        # 3 second timeout to prevent hanging independent processes
        latest_tag=$(curl -s --max-time 3 "$REPO_URL" | jq -r .tag_name 2>/dev/null)
        
        if [[ -n "$latest_tag" && "$latest_tag" != "null" ]]; then
            echo "$latest_tag" > "$UPDATE_FILE"
        fi
    ) &
}

# Foreground: Checks if a new version was found in PREVIOUS run
check_update_status_foreground() {
    if [[ -f "$UPDATE_FILE" ]]; then
        local latest_version
        latest_version=$(cat "$UPDATE_FILE")
        
        if version_gt "$latest_version" "$VERSION"; then
             # Version Mismatch - likely an update
             # We can do a smarter semantic check if needed, but for now difference = update
             # Note: This might flag dev versions, but acceptable.
             
             echo -e "${Cyan}---------------------------------------------------${RESET}"
             echo -e "${BOLD}Update Available:${RESET} ${GREEN}$latest_version${RESET} (Current: v$VERSION)"
             echo -e "Get it at: https://github.com/cryptochrome/dovi_convert"
             echo -e "${Cyan}---------------------------------------------------${RESET}"
             echo ""
        fi
    fi
}

cmd_update_check_manual() {
    echo -e "${BOLD}Checking for updates...${RESET}"
    local latest_tag
    latest_tag=$(curl -s --max-time 10 "$REPO_URL" | jq -r .tag_name 2>/dev/null)
    
    if [[ -z "$latest_tag" || "$latest_tag" == "null" ]]; then
        echo -e "${RED}Error: Could not fetch update info from GitHub.${RESET}"
        return 1
    fi
    
    echo "Latest version on GitHub: $latest_tag"
    echo "Installed version:        v$VERSION"
    
     if version_gt "$latest_tag" "$VERSION"; then
         echo -e "\n${GREEN}Update Available!${RESET}"
         echo "Download at: https://github.com/cryptochrome/dovi_convert"
     else
         echo -e "\n${GREEN}You are up to date.${RESET}"
     fi
}

# --- PQ EOTF Helper (Code Value -> Nits) ---
pq_to_nits() {
    local code_val="$1"
    if [[ -z "$code_val" ]]; then echo "0"; return; fi
    awk -v cv="$code_val" 'BEGIN {
        # ST.2084 Constants
        m1 = 2610.0 / 16384.0;
        m2 = 2523.0 / 32.0;    # 2523/4096 * 128 = 2523/32
        c1 = 3424.0 / 4096.0;
        c2 = 2413.0 / 128.0;   # 2413/4096 * 32 = 2413/128
        c3 = 2392.0 / 128.0;   # 2392/4096 * 32 = 2392/128
        
        # Normalize 12-bit code value (0-4095) to 0-1
        V = cv / 4095.0;

        if (V <= 0) { print 0; exit; }
        
        # Calculate V^(1/m2)
        vp = exp(log(V) / m2);

        # Calculate max(vp - c1, 0)
        num = vp - c1;
        if (num < 0) num = 0;

        # Calculate c2 - c3*vp
        den = c2 - c3 * vp;
        if (den == 0) den = 0.000001; # Avoid div/0

        # Calculate R = (num / den)^(1/m1)
        base_val = num / den;
        if (base_val < 0) base_val = 0;
        
        nits = 10000.0 * exp(log(base_val) / m1);
        printf "%.0f", nits
    }'
}

# ------------------------------------------------------------------------------
# DEEP SCAN ANALYZER
# ------------------------------------------------------------------------------

# Analyzes the RPU of a file to detect "Active Reconstruction" (Complex FEL).
# Sets globals: FEL_VERDICT (SAFE|COMPLEX|UNKNOWN) and FEL_REASON
# Analyzes the RPU of a file to detect "Active Reconstruction" (Complex FEL).
# Sets globals: FEL_VERDICT (SAFE|COMPLEX|UNKNOWN) and FEL_REASON
check_fel_complexity() {
    local file="$1"
    FEL_VERDICT="UNKNOWN"
    FEL_REASON="Analysis failed"

    # 1. Determine Probe Points (10%, 50%, 90%)
    local duration_ms
    duration_ms=$(mediainfo --Output="Video;%Duration%" "$file" 2>/dev/null | cut -d. -f1)
    
    local timestamps=()
    if [[ -z "$duration_ms" ]] || [[ "$duration_ms" -lt 10000 ]]; then
        timestamps=(0) # Fallback to start
    else
        local dur_sec=$(echo "$duration_ms / 1000" | bc)
        # Probe at 10 points (5% to 95%) for maximum coverage of sparse peaks
        timestamps=(
            $(echo "$dur_sec * 0.05" | bc | cut -d. -f1)
            $(echo "$dur_sec * 0.15" | bc | cut -d. -f1)
            $(echo "$dur_sec * 0.25" | bc | cut -d. -f1)
            $(echo "$dur_sec * 0.35" | bc | cut -d. -f1)
            $(echo "$dur_sec * 0.45" | bc | cut -d. -f1)
            $(echo "$dur_sec * 0.55" | bc | cut -d. -f1)
            $(echo "$dur_sec * 0.65" | bc | cut -d. -f1)
            $(echo "$dur_sec * 0.75" | bc | cut -d. -f1)
            $(echo "$dur_sec * 0.85" | bc | cut -d. -f1)
            $(echo "$dur_sec * 0.95" | bc | cut -d. -f1)
        )
    fi

    # 2. Determine Base Layer Peak (Default 1000)
    local bl_peak=1000
    local detected_peak=""
    
    # Try MediaInfo first (reliable for mastering metadata)
    # Output format example: "min: 0.0001 cd/m2, max: 1000 cd/m2"
    local mi_out
    mi_out=$(mediainfo --Output="Video;%MasteringDisplay_Luminance%" "$file" 2>/dev/null)
    
    if [[ "$mi_out" == *"max:"* ]]; then
         detected_peak=$(echo "$mi_out" | grep -oE "max: [0-9]+" | awk '{print $2}')
    elif [[ "$mi_out" =~ ^[0-9]+ ]]; then
         detected_peak=$(echo "$mi_out" | cut -d. -f1)
    fi
    
    # Fallback to ffprobe if empty
    if [[ -z "$detected_peak" ]]; then
         detected_peak=$(ffprobe -v error -select_streams v:0 -show_entries side_data=max_luminance -of default=noprint_wrappers=1:nokey=1 "$file" | head -n1)
    fi
     
    # Handle Rational (X/Y) or Integer
    if [[ "$detected_peak" == */* ]]; then
         bl_peak=$(echo "scale=0; $detected_peak" | bc -l | cut -d. -f1)
    elif [[ "$detected_peak" =~ ^[0-9]+$ ]]; then
         bl_peak=$detected_peak
    fi
     
    # Sanity check (Mastering displays are usually 1000 or 4000)
    # If < 100, assume error and default to 1000. 
    # NOTE: Some early HDR is 400 nits, but rare. 100 is definitely an error or SDR.
    if (( bl_peak < 100 )); then bl_peak=1000; fi

    local complex_signal=false
    local probe_count=0
    local threshold=$(( bl_peak + 50 ))

    if [[ "$DEBUG_MODE" == true ]]; then
         echo "[Deep Scan Debug] Base Layer Peak: $bl_peak nits (Threshold: $threshold)" >> dovi_convert_debug.log
    fi

    for t in "${timestamps[@]}"; do
        local temp_hevc="probe_${t}_$(date +%s)_$$.hevc"
        local temp_rpu="${temp_hevc}.rpu"
        local temp_json="${temp_hevc}.json"

        # Extract 1 second of HEVC
        if [[ "$DEBUG_MODE" == true ]]; then
            ffmpeg -analyzeduration 100M -probesize 100M -ss "$t" -i "$file" -map 0:v:0 -c:v copy -an -sn -dn -bsf:v hevc_mp4toannexb -f hevc -t 1 "$temp_hevc" >> dovi_convert_debug.log 2>&1 < /dev/null
        else
            ffmpeg -v error -analyzeduration 100M -probesize 100M -ss "$t" -i "$file" -map 0:v:0 -c:v copy -an -sn -dn -bsf:v hevc_mp4toannexb -f hevc -t 1 "$temp_hevc" 2>/dev/null < /dev/null
        fi

        if [[ ! -s "$temp_hevc" ]]; then rm -f "$temp_hevc"; continue; fi

        # Extract RPU
        if [[ "$DEBUG_MODE" == true ]]; then
             dovi_tool extract-rpu "$temp_hevc" -o "$temp_rpu" >> dovi_convert_debug.log 2>&1
        else
             dovi_tool extract-rpu "$temp_hevc" -o "$temp_rpu" >/dev/null 2>&1
        fi
        rm -f "$temp_hevc"

        if [[ ! -s "$temp_rpu" ]]; then rm -f "$temp_rpu"; continue; fi

        # Analyze L1
        if [[ "$DEBUG_MODE" == true ]]; then
             dovi_tool export -i "$temp_rpu" -d all="$temp_json" >> dovi_convert_debug.log 2>&1
        else
             dovi_tool export -i "$temp_rpu" -d all="$temp_json" >/dev/null 2>&1
        fi
        rm -f "$temp_rpu"
        
        if [[ ! -s "$temp_json" ]]; then rm -f "$temp_json"; continue; fi

        ((probe_count++))
        
        # Check EL Type (MEL = Safe)
        # Using grep on temp_json directly (faster than cat/tr)
        if grep -q '"el_type":"MEL"' "$temp_json"; then
             FEL_VERDICT="SAFE"
             FEL_REASON="Minimal Enhancement Layer (MEL) Detected"
             rm -f "$temp_json"
             return 0
        fi
        
        # Extract L1 Max
        local l1_max=""
        if command -v jq >/dev/null; then
             # Use robust recursive search for Level1 or l1, finding max_pq or max
             # Use file directly!
             l1_max=$(jq '[.. | .Level1? // .l1? | .max_pq? // .max? // empty] | max' "$temp_json" 2>/dev/null)
             
             # Debug logging if extraction fails
             if [[ -z "$l1_max" || "$l1_max" == "null" ]]; then
                 if [[ "$DEBUG_MODE" == true ]]; then
                     echo "[Deep Scan Debug] Probe @ ${t}s : L1 Extraction Failed via jq." >> dovi_convert_debug.log
                     echo "[Deep Scan Debug] JSON Start: $(head -c 200 "$temp_json")" >> dovi_convert_debug.log
                 fi
                 l1_max=""
             fi
        else
             # Regex Fallback
             # We need flat json for grep regex
             local flat_json
             flat_json=$(tr -d '[:space:]' < "$temp_json")
             l1_max=$(echo "$flat_json" | grep -oE '"(Level1|l1|L1)":\{[^}]*"(max|max_pq|Max)":[0-9]+' | grep -oE '[0-9]+$' | sort -rn | head -1)
        fi

        # Cleanup JSON now (unless debugging?)
        # Actually keep it if debug mode? No, too many files.
        rm -f "$temp_json"


        if [[ "$l1_max" == "null" ]]; then l1_max=""; fi

        if [[ -n "$l1_max" ]]; then
             # Convert PQ Code Value to Nits for accurate comparison
             local l1_nits=$(pq_to_nits "$l1_max")
             
             if [[ "$DEBUG_MODE" == true ]]; then
                  echo "[Deep Scan Debug] Probe @ ${t}s : L1 Raw=$l1_max -> ${l1_nits} nits vs Threshold=$threshold (BL=$bl_peak)" >> dovi_convert_debug.log
             fi

             if (( l1_nits > threshold )); then
                 complex_signal=true
                 FEL_REASON="Active Reconstruction (L1: ${l1_nits} nits > BL: ${bl_peak} nits @ ${t}s)"
                 break
             fi
        elif [[ "$DEBUG_MODE" == true ]]; then
             echo "[Deep Scan Debug] Probe @ ${t}s : No L1 Found." >> dovi_convert_debug.log
        fi
    done

    if [[ "$probe_count" -eq 0 ]]; then
        FEL_REASON="Extraction failed (No probes succeeded)"
        # Default to Complex if we can't read it (Safety First)
        FEL_VERDICT="COMPLEX"
        return 0
    fi

    if [[ "$complex_signal" == true ]]; then
        FEL_VERDICT="COMPLEX"
        return 0
    fi

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
    echo -e "${BOLD}dovi_convert v${VERSION}${RESET}"
    echo "Usage:"
    echo -e "  ${BOLD}dovi_convert -help                   : SHOW DETAILED MANUAL & EXAMPLES${RESET}"
    echo "  dovi_convert -check                  : Analyze all MKV files in current directory."
    echo "  dovi_convert -check   [file]         : Analyze profile of a specific file."
    echo "  dovi_convert -inspect [file] [-safe] : Inspect full RPU structure (Active Brightness Check)."
    echo "  dovi_convert -convert [file]         : Convert a file to DV Profile 8.1."
    echo "  dovi_convert -convert [file] -safe   : Convert using Safe Mode (Disk Extraction)."
    echo "  dovi_convert -batch   [depth] [-y]   : Batch convert folder (-y to auto-confirm)."
    echo "  dovi_convert -cleanup [-r]    [-y]   : Delete tool backups (Optional: -r recursive)."
    echo "  dovi_convert -update-check           : Check for software updates."
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
    echo -e "  1. ${GREEN}Simple FEL / MEL${RESET}: No active brightness expansion detected. Likely safe to convert. (Default)"
    echo -e "  2. ${RED}Complex FEL${RESET}: Expands luminance beyond base layer luminance."
    echo "     Converting these files discards brightness data and will lead to incorrect"
    echo "     tone mapping. The tool will automatically skip these files."
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
    echo -e "       Scan directory and convert safe Profile 7 files."
    echo -e "       Default depth is 1 (current dir). Use '-batch 2' for subfolders."
    echo ""
    echo "       Options:"
    echo -e "         ${BOLD}-y${RESET}               Skip confirmation prompts (Auto-Yes)."
    echo -e "         ${BOLD}-include-simple${RESET}  Allow auto-conversion of Simple FEL files in Auto-Yes mode."
    echo -e "         ${BOLD}-force${RESET}           Force convert 'Complex FEL' files (Apply to all)."
    echo -e "         ${BOLD}-delete${RESET}          Auto-delete backups after successful conversion."
    echo ""
    echo -e "  ${BOLD}-cleanup${RESET}"
    echo -e "       Scans for and deletes ${CYAN}*.mkv.bak.dovi_convert${RESET} files in the current directory."
    echo -e "       ${BOLD}Safety Check:${RESET} Checks if 'Parent' MKV exists before deleting orphan backups."
    echo ""
    echo "       Options:"
    echo -e "         ${BOLD}-r${RESET}       Recursive scan."
    echo -e "         ${BOLD}-r${RESET}       Recursive scan."
    echo -e "         ${BOLD}-y${RESET}       Skip confirmation prompts."
    echo ""
    echo -e "  ${BOLD}-update-check${RESET}"
    echo "       Checks GitHub permissions for the latest release."
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
    
    # Trigger background update check on clean exit
    check_for_updates_background
    
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
    mkv_json=$(mkvmerge -J "$file" 2>/dev/null)
    local mkv_res=$?

    if [[ $mkv_res -ne 0 ]]; then
        MI_INFO_STRING="MKVMERGE_FAIL"
        return
    fi
    VIDEO_TRACK_ID=$(echo "$mkv_json" | jq -r '.tracks // [] | .[] | select(.type=="video") | .id' | head -n 1)

    if [[ -z "$VIDEO_TRACK_ID" ]]; then
        MI_INFO_STRING="NO_TRACK"
        return
    fi

    VIDEO_DELAY=$(echo "$mkv_json" | jq -r ".tracks // [] | .[] | select(.id==$VIDEO_TRACK_ID) | .properties.minimum_timestamp // 0")
    VIDEO_LANG=$(echo "$mkv_json" | jq -r ".tracks // [] | .[] | select(.id==$VIDEO_TRACK_ID) | .properties.language // \"und\"")
    VIDEO_NAME=$(echo "$mkv_json" | jq -r ".tracks // [] | .[] | select(.id==$VIDEO_TRACK_ID) | .properties.track_name // empty")

    # 2. Get Dolby Profile
    local mi_json
    mi_json=$(mediainfo --Output=JSON "$file")

    MI_INFO_STRING=$(echo "$mi_json" | jq -r '.media.track // [] | .[] | select(.["@type"]=="Video") | "\(.HDR_Format) \(.HDR_Format_Profile) \(.CodecID)"' | tr '\n' ' ')
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

    if [[ "$MI_INFO_STRING" == "MKVMERGE_FAIL" ]]; then
        DOVI_STATUS="${RED}Error: mkvmerge failed (Check Locale/Install)${RESET}"; ACTION="ERROR"; return
    fi

    # 3. Decision Matrix
    if [[ "$MI_INFO_STRING" == *"dvhe.07"* ]] || [[ "$MI_INFO_STRING" == *"Profile 7"* ]]; then
        # PROFILE 7 DETECTED
        
        # DEEP SCAN (Always runs now, -quick removed)
        check_fel_complexity "$file"
        
        if [ "$FEL_VERDICT" == "COMPLEX" ]; then
            DOVI_STATUS="${RED}DV Profile 7 FEL (Complex)${RESET}"
            if [ "$FORCE_MODE" = true ]; then
                ACTION="${RED}CONVERT (FORCED)${RESET}"
            else
                ACTION="${RED}SKIP (Complex FEL)${RESET}"
            fi
        elif [ "$FEL_VERDICT" == "SAFE" ]; then
            if [[ "$FEL_REASON" == *"MEL"* ]]; then
                 DOVI_STATUS="${GREEN}DV Profile 7 MEL (Safe)${RESET}"
                 ACTION="${GREEN}CONVERT${RESET}"
            else
                 DOVI_STATUS="${CYAN}DV Profile 7 FEL (Simple)${RESET}" # Cyan for Statistical Safety
                 ACTION="${CYAN}CONVERT*${RESET}"
            fi
        else
            DOVI_STATUS="${YELLOW}DV Profile 7 (Check Failed)${RESET}"
            ACTION="${YELLOW}MANUAL CHECK${RESET}"
        fi

    elif [[ "$MI_INFO_STRING" == *"dvhe.08"* ]] || [[ "$MI_INFO_STRING" == *"Profile 8"* ]]; then
        DOVI_STATUS="DV Profile 8.1"; ACTION="IGNORE"
    elif [[ "$MI_INFO_STRING" == *"dvhe.05"* ]] || [[ "$MI_INFO_STRING" == *"Profile 5"* ]]; then
        DOVI_STATUS="${YELLOW}DV Profile 5 (Stream)${RESET}"; ACTION="IGNORE"
    elif [[ "$MI_INFO_STRING" == *"Dolby Vision"* ]]; then
        DOVI_STATUS="${YELLOW}DV Unknown Profile${RESET}"; ACTION="IGNORE"
    else
        # Granular Detection
        if [[ "$MI_INFO_STRING" == *"2094"* ]]; then
            DOVI_STATUS="HDR10+"
        elif [[ "$MI_INFO_STRING" == *"HLG"* ]] || [[ "$MI_INFO_STRING" == *"Hybrid Log Gamma"* ]]; then
            DOVI_STATUS="HLG"
        elif [[ "$MI_INFO_STRING" == *"2086"* ]] || [[ "$MI_INFO_STRING" == *"HDR10"* ]]; then
            DOVI_STATUS="HDR10"
        else
            DOVI_STATUS="SDR"
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

    # Simple FEL Advisory
    if [[ "$DOVI_STATUS" == *"FEL (Simple)"* ]]; then
        echo -e "${YELLOW}[!] WARNING: This is a 'Simple FEL' file.${RESET}"
        echo "    Deep scan found no active brightness expansion."
        echo "    Use -inspect for a full RPU analysis if in doubt."
        printf "Proceed with conversion? (y/N) "
        read -r REPLY
        if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
            echo "Conversion cancelled."
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
    
    local simple_fel_queue=()

    while IFS= read -r -d '' file; do
        analyze_file "$file"
        
        # Check specific status for queuing logic
        local is_simple=false
        if [[ "$DOVI_STATUS" == *"FEL (Simple)"* ]]; then is_simple=true; fi

        if [[ "$ACTION" == *CONVERT* ]]; then
            conversion_queue+=("$file")
            
            if [[ "$ACTION" == *"FORCED"* ]]; then
                ((forced_count++))
            elif [ "$is_simple" = true ]; then
                ((simple_count++))
                simple_fel_queue+=("$file")
            else
                # Clean MEL is just count
                ((simple_count++)) 
            fi

            local f_size=$(get_file_size "$file")
            total_batch_size=$((total_batch_size + f_size))

        elif [[ "$ACTION" == "IGNORE" ]]; then
            ((ignored_count++))
        elif [[ "$FEL_VERDICT" == "COMPLEX" ]]; then
            ((complex_count++))
        else
            ((skipped_count++))
        fi
    done < <(find . -maxdepth "$max_depth" -name "*.mkv" ! -name "._*" ! -path "*/._*/*" -print0 | sort -z)

    if [[ ${#conversion_queue[@]} -eq 0 && $complex_count -eq 0 ]]; then 
         echo "No Profile 7 files found (Ignored: $ignored_count)."
         return 0
    fi

    # --- Interactive Overview ---
    local queue_count=${#conversion_queue[@]}
    local total_size_gb=$(human_size_gb $total_batch_size)
    local simple_fel_count=${#simple_fel_queue[@]}
    local mel_count=$((simple_count - simple_fel_count))

    echo -e "\n${BOLD}Batch Overview:${RESET}"
    
    if [[ $mel_count -gt 0 ]]; then
        echo -e "  Convert:        ${GREEN}$mel_count${RESET}   (MEL - Safe)"
    fi
    if [[ $simple_fel_count -gt 0 ]]; then
        echo -e "  Convert:        ${CYAN}$simple_fel_count${RESET}   (Simple FEL - Likely Safe)"
    fi
    if [[ $forced_count -gt 0 ]]; then
        echo -e "  Convert:        ${YELLOW}$forced_count${RESET}   (Complex FEL - Forced)"
    fi
    if [[ $complex_count -gt 0 ]]; then
        echo -e "  Skip:           ${RED}$complex_count${RESET}   (Complex FEL)"
    fi
    echo -e "  Queue Size:     ${CYAN}$total_size_gb${RESET} ($queue_count files)"

    # --- SAFETY GATE ---
    if [[ "$AUTO_YES" == true ]]; then
        # Check for Simple FEL without permission
         if [[ $simple_fel_count -gt 0 ]] && [[ "$INCLUDE_SIMPLE" == false ]]; then
              echo -e "\n${RED}[!] SAFETY STOP:${RESET} Simple FEL files detected in Auto-Mode."
              echo -e "    Warning: Batch includes $simple_fel_count 'Simple FEL' files."
              echo -e "    For details, run -check first."
              echo -e "    To automate their conversion, you must add: ${BOLD}-include-simple${RESET}"
              echo -e "    Skipping batch execution."
              return 1
         fi
        
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

        if [[ $simple_fel_count -gt 0 ]]; then
             echo -e "\n${YELLOW}[!] WARNING: Batch includes $simple_fel_count 'Simple FEL' files.${RESET}"
             echo -e "    For details, run -check first."
             printf "    Proceed with these files? (y/N) "
        else
             printf "\nProceed with conversion? (Y/n) "
        fi
        
        read -r REPLY
        if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
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
    local success_simple_fel_count=0

    for file in "${conversion_queue[@]}"; do
        if [[ "$ABORT_REQUESTED" == true ]]; then break; fi

        echo "---------------------------------------------------"
        echo -e "${BOLD}[$current_idx/$queue_count]${RESET} Processing: $(basename "$file")"
        
        # Re-analyze to ensure DOVI_STATUS/FEL_VERDICT is fresh for this file
        # (Needed because global vars are stale from the initial scan loop)
        analyze_file "$file" >/dev/null

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
                if [[ "$DOVI_STATUS" == *"Simple"* ]]; then
                     ((success_simple_fel_count++))
                fi
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
        local mel_count=$((success_simple_count - success_simple_fel_count))
        local breakdown=""
        if [[ $success_simple_fel_count -gt 0 ]]; then
             breakdown="(${CYAN}$success_simple_fel_count Simple FEL${RESET} / ${GREEN}$mel_count MEL${RESET})"
        else
             breakdown="(${GREEN}MEL / Safe${RESET})"
        fi
        echo -e "  - Converted:   ${GREEN}$success_simple_count${RESET}   $breakdown"
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
    get_video_details "$file"
    
    if [[ "$MI_INFO_STRING" != *"dvhe.07"* ]] && [[ "$MI_INFO_STRING" != *"Profile 7"* ]]; then
        echo -e "${RED}Error: File is not Dolby Vision Profile 7.${RESET}"
        echo -e "Detected: $DOVI_STATUS (Info: $MI_INFO_STRING)"
        exit 1
    fi

    echo ""
    echo "==================================================="
    echo "FULL RPU STRUCTURE INSPECTION"
    echo "==================================================="
    echo -e "File:       ${BOLD}$(basename -- "$file")${RESET}"
    echo -e "Format:     DV Profile 7 (Scanning...)"
    echo "---------------------------------------------------"
    
    # --- MEL Fast-Pass (Pre-Flight) ---
    start_spinner "Checking EL Structure (Pre-Flight)... "
    local pf_hevc="inspect_pf_$(date +%s)_$$.hevc"
    local pf_rpu="${pf_hevc}.rpu"
    local pf_json="${pf_hevc}.json"
    local mel_detected=false

    ffmpeg -v error -y -i "$file" -c:v copy -bsf:v hevc_mp4toannexb -f hevc -t 1 "$pf_hevc" 2>/dev/null < /dev/null
    if [[ -s "$pf_hevc" ]]; then
         dovi_tool extract-rpu "$pf_hevc" -o "$pf_rpu" >/dev/null 2>&1
         if [[ -s "$pf_rpu" ]]; then
              dovi_tool export -i "$pf_rpu" -d all="$pf_json" >/dev/null 2>&1
              if [[ -s "$pf_json" ]]; then
                   if grep -q '"el_type":"MEL"' "$pf_json"; then
                        mel_detected=true
                   fi
              fi
         fi
    fi
    rm -f "$pf_hevc" "$pf_rpu" "$pf_json"
    stop_spinner

    if [[ "$mel_detected" == true ]]; then
         printf "\r\e[KChecking EL Structure... Done (MEL Detected).\n"
         echo "---------------------------------------------------"
         echo -e "${BOLD}VERDICT:${RESET}    ${GREEN}MEL (Minimal Enhancement Layer)${RESET}"
         echo "---------------------------------------------------"
         echo -e "${BOLD}ADVISORY:${RESET}\nFile is identified as MEL (empty enhancement layer).\nIt contains no video data to discard.\nAbsolutely safe to convert."
         echo "==================================================="
         echo ""
         return 0
    fi
    printf "\r\e[KChecking EL Structure... Done (FEL Detected - Proceeding).\n"

    local temp_rpu="inspect_$(date +%s)_$$.rpu"
    local temp_json="inspect_$(date +%s)_$$.json"
    local use_safe_mode=$SAFE_MODE

    # 2. Extract Full RPU
    while true; do
        if [ "$use_safe_mode" = false ]; then
            start_spinner "Extracting RPU (Standard Pipe)... "
            set -o pipefail
            (ffmpeg -v error -i "$file" -map 0:$VIDEO_TRACK_ID -c:v copy -bsf:v hevc_mp4toannexb -f hevc - 2>/dev/null \
            | dovi_tool extract-rpu - -o "$temp_rpu" >/dev/null 2>&1)
            local status=$?
            set +o pipefail
            stop_spinner

            if [ $status -eq 0 ] && [ -s "$temp_rpu" ]; then
                printf "\r\e[KExtracting RPU... Done.\n"
                break
            else
                printf "\r\e[KExtracting RPU... ${RED}Failed.${RESET}\n"
                rm -f "$temp_rpu"
                
                if [ "$AUTO_YES" = true ]; then
                     echo -e "${YELLOW}Retrying with Safe Mode (Auto-Yes).${RESET}"
                     use_safe_mode=true
                     continue
                else
                     read -p "Retry using Safe Mode (Extraction to Disk)? [Y/n] " -n 1 -r
                     echo ""
                     if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
                         use_safe_mode=true; continue
                     else
                         echo -e "${RED}Aborted.${RESET}"; exit 1
                     fi
                fi
            fi
        else
            local raw_temp="inspect_temp_$(date +%s)_$$.hevc"
            start_spinner "Extracting Track (Safe Mode)... "
            mkvextract "$file" tracks "$VIDEO_TRACK_ID:$raw_temp" >/dev/null 2>&1
            local res=$?
            stop_spinner
            
            if [ $res -ne 0 ]; then
                echo -e "\n${RED}Extracting Track Failed.${RESET}"; rm -f "$raw_temp"; exit 1
            fi
            printf "\r\e[KExtracting Track... Done.\n"

            start_spinner "Extracting RPU... "
            dovi_tool extract-rpu "$raw_temp" -o "$temp_rpu" >/dev/null 2>&1
            local status=$?
            stop_spinner
            rm -f "$raw_temp"

            if [ $status -eq 0 ] && [ -s "$temp_rpu" ]; then
                printf "\r\e[KExtracting RPU... Done.\n"
                break
            else
                echo -e "\n${RED}RPU Extraction Failed.${RESET}"; rm -f "$temp_rpu"; exit 1
            fi
        fi
    done

    # 3. Export to JSON (Capture stderr to silence 'Parsing...' noise)
    start_spinner "Exporting Metadata (Slow)... "
    dovi_tool export -i "$temp_rpu" -d all="$temp_json" >/dev/null 2>&1
    local export_res=$?
    stop_spinner
    
    rm -f "$temp_rpu"

    if [[ $export_res -ne 0 ]] || [[ ! -s "$temp_json" ]]; then
         echo -e "\r\e[KExporting Metadata... ${RED}Failed.${RESET}"
         rm -f "$temp_json"
         exit 1
    fi
    printf "\r\e[KExporting Metadata... Done.\n"

    # 4. Analyze Statistics
    start_spinner "Calculating Peak Brightness (99.9th)... "
    
    # We want both the count ($c) and the peak ($a[idx])
    # Bug Fix: Use recursive search (..) to find Level1/l1/max_pq anywhere, matching Deep Scan logic.
    local stats_output
    stats_output=$(jq -r '[.. | .Level1? // .l1? | .max_pq? // .max? // empty] | map(select(. != null)) | .[]' "$temp_json" 2>/dev/null | sort -n | awk '
      BEGIN {c=0}
      {a[c++]=$1}
      END {
        if (c==0) {print "0 0"; exit}
        idx=int(c*0.999)
        print c " " a[idx]
      }
    ')
    stop_spinner
    rm -f "$temp_json"

    # Split output into vars
    local frame_count=$(echo "$stats_output" | cut -d' ' -f1)
    local robust_peak=$(echo "$stats_output" | cut -d' ' -f2)

    # Round to integer if needed and CONVERT TO NITS
    if [[ -n "$robust_peak" ]]; then
        robust_peak=$(printf "%.0f" "$robust_peak")
        robust_peak=$(pq_to_nits "$robust_peak")
    else
        robust_peak=0
    fi
    printf "\r\e[KCalculating Peak Brightness... Done.\n"
    
    # 5. Verdict Logic
    # 5. Verdict Logic
    local raw_bl_peak=""
    local mi_out_insp
    mi_out_insp=$(mediainfo --Output="Video;%MasteringDisplay_Luminance%" "$file" 2>/dev/null)
    
    if [[ "$mi_out_insp" == *"max:"* ]]; then
         raw_bl_peak=$(echo "$mi_out_insp" | grep -oE "max: [0-9]+" | awk '{print $2}')
    elif [[ "$mi_out_insp" =~ ^[0-9]+ ]]; then
         raw_bl_peak=$(echo "$mi_out_insp" | cut -d. -f1)
    fi
    
    # Fallback to ffprobe
    if [[ -z "$raw_bl_peak" ]]; then
         raw_bl_peak=$(ffprobe -v error -select_streams v:0 -show_entries side_data=max_luminance -of default=noprint_wrappers=1:nokey=1 "$file" | head -n1 | cut -d. -f1)
    fi
    
    local bl_peak="${raw_bl_peak:-1000}" 
    
    # Sanity check BL
    if (( bl_peak < 100 )); then bl_peak=1000; fi

    local threshold=$(( bl_peak + 50 ))
    local diff=$(( robust_peak - bl_peak ))
    local verdict=""
    local advisory=""

    if [[ "$frame_count" -eq 0 ]]; then
         # Special Warning for Empty L1
         verdict="${YELLOW}NO L1 METADATA${RESET}"
         advisory="${RED}WARNING:${RESET} No valid L1 brightness metadata found in FEL.\nThis is unusual for non-MEL files. Proceed with caution."
         robust_peak="N/A"
         diff="N/A"
    elif [ "$robust_peak" -gt "$threshold" ]; then
         verdict="${RED}COMPLEX FEL (Active Brightness Expansion)${RESET}"
         advisory="${BOLD}ADVISORY:${RESET}\nFEL Peak ($robust_peak nits) exceeds Base Layer ($bl_peak nits).\nThis indicates active brightness expansion in the FEL.\nConversion will likely cause clipping or tone-mapping errors."
    else
         verdict="${GREEN}SIMPLE / SAFE${RESET}"
         advisory="${BOLD}ADVISORY:${RESET}\nFEL Peak ($robust_peak nits) is within safe range of Base Layer ($bl_peak nits).\nSafe to convert."
    fi

    printf "%-22s %s nits\n" "Base Layer Peak (MDL):" "${bl_peak}"
    printf "%-22s %s frames analyzed\n" "L1 Analysis:" "${frame_count}"
    printf "%-22s %s nits\n" "FEL Peak Brightness:" "${robust_peak}"
    
    if [ "$robust_peak" -gt "$threshold" ]; then
         printf "%-22s " "Brightness Expansion:"
         echo -e "${RED}+${diff} nits (Active)${RESET}"
    else
         printf "%-22s " "Brightness Expansion:"
         echo -e "${GREEN}None (Safe)${RESET}"
    fi

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

    if [[ "$DOVI_STATUS" == *"FEL (Simple)"* ]]; then
        echo ""
        echo "================================================================================================"
        echo -e "${BOLD}*ADVISORY: UNDERSTANDING 'SIMPLE' (CYAN) VERDICTS${RESET}"
        echo "------------------------------------------------------------------------------------------------"
        echo -e "${BOLD}What is 'Simple FEL'?${RESET}"
        echo "It means the deep scan detected no active brightness expansion over the Base Layer. This"
        echo "suggests the file is likely safe to convert. But:"
        echo ""
        echo -e "${BOLD}How accurate is the deep scan?${RESET}"
        echo "The script takes 10 samples at different timestamps of the video to analyze peak brightness in"
        echo "the FEL. While this is statistically accurate enough to determine whether the FEL expands luminance"
        echo "over the Base Layer, it can't guarantee a definitive result. If accurate preservation is paramount"
        echo "for a specific file, please verify it with -inspect before converting."
        echo "================================================================================================"
    fi
}

cmd_check_all() {
    local max_depth="${1:-1}"
    
    # 1. Build Header Message
    local scan_type="Deep Scan"
    
    local location="in current directory"
    if [[ "$max_depth" -gt 1 ]]; then location="recursively ($max_depth levels deep)"; fi
    
    echo -e "${CYAN}Running $scan_type $location...${RESET}"
    
    # 2. Print Table Header
    printf "%-50s %-36s %s\n" "Filename" "Format" "Action"
    echo "------------------------------------------------------------------------------------------------"
    
    # 3. Iterate
    local simple_count=0
    while IFS= read -r -d '' file; do
        analyze_file "$file"
        local name=$(basename -- "$file")
        # Truncate filename (47 chars + '...' = 50 to fit column width)
        if [ ${#name} -gt 50 ]; then name="${name:0:47}..."; fi

        # Track Simple FEL for footer
        if [[ "$DOVI_STATUS" == *"FEL (Simple)"* ]]; then
             ((simple_count++))
        fi

        printf "%-50s %-36b %b\n" "$name" "${DOVI_STATUS}" "${ACTION}"
    done < <(find . -maxdepth "$max_depth" -name "*.mkv" ! -name "._*" ! -path "*/._*/*" -print0 | sort -z)

    # 4. Conditional Advisory
    if [ "$simple_count" -gt 0 ]; then
        echo ""
        echo "================================================================================================"
        echo -e "${BOLD}*ADVISORY: UNDERSTANDING 'SIMPLE' (CYAN) VERDICTS${RESET}"
        echo "------------------------------------------------------------------------------------------------"
        echo -e "${BOLD}What is 'Simple FEL'?${RESET}"
        echo "It means the deep scan detected no active brightness expansion over the Base Layer. This"
        echo "suggests the file is likely safe to convert. But:"
        echo ""
        echo -e "${BOLD}How accurate is the deep scan?${RESET}"
        echo "The script takes 10 samples at different timestamps of the video to analyze peak brightness in"
        echo "the FEL. While this is statistically accurate enough to determine whether the FEL expands luminance"
        echo "over the Base Layer, it can't guarantee a definitive result. If accurate preservation is paramount"
        echo "for a specific file, please verify it with -inspect before converting."
        echo "================================================================================================"
    fi
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
        -include-simple) INCLUDE_SIMPLE=true ;;
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
    check_update_status_foreground
    print_usage
    check_for_updates_background
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
    -update-check)
        cmd_update_check_manual
        ;;
    -help|--help)
        check_update_status_foreground
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

# Trigger background update check on clean exit
check_for_updates_background
