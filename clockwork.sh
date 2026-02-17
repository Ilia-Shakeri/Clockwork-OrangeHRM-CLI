#!/bin/bash

# ==============================================================================
# Project:     Clockwork OrangeHRM CLI
# Description: Extract work hours from Self-Hosted OrangeHRM (MariaDB).
# Author:      Ilia Shakeri
# License:     CC0 1.0 Universal (Public Domain)
# ==============================================================================

# --- Colors & Styling ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- Configuration Defaults ---
DB_CONTAINER="orangehrm_mariadb"
DB_NAME="orangehrm"
DB_USER="orangehrm"
DB_PASS=""
LOG_DIR="./logs"

# --- Globals ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_USERS_FILE="$SCRIPT_DIR/users.txt"
RUN_TMP_DIR=""

# --- Trap Ctrl+C for clean exit ---
cleanup() {
    if [[ -n "$RUN_TMP_DIR" && -d "$RUN_TMP_DIR" ]]; then
        rm -rf "$RUN_TMP_DIR" >/dev/null 2>&1
    fi
}
trap 'cleanup; echo -e "\n${YELLOW}[!] Exiting...${NC}"; exit 0' SIGINT

# --- Helper Functions ---

# Function to write to log file without colors
log_entry() {
    local message="$1"
    mkdir -p "$LOG_DIR"
    local today_log="$LOG_DIR/$(date +%Y-%m-%d).log"
    echo -e "$message" | sed 's/\x1b\[[0-9;]*m//g' >> "$today_log"
}

# Wrapper to print to screen AND log file
print_and_log() {
    echo -e "$1"
    log_entry "$1"
}

# Print error and exit
die() {
    print_and_log "${RED}[X] $1${NC}"
    cleanup
    exit 1
}

# Yes/No prompt helper (default: Yes)
confirm_yes_default() {
    local prompt="$1"
    local ans
    read -p "$prompt [Y/n]: " ans
    ans="${ans:-Y}"
    [[ "$ans" == "Y" || "$ans" == "y" ]]
}

# Expand a leading ~ in a path safely
expand_tilde() {
    local p="$1"
    if [[ "$p" == "~"* ]]; then
        echo "${p/#\~/$HOME}"
    else
        echo "$p"
    fi
}

# Escape HTML entities for safe HTML output
html_escape() {
    echo "$1" | sed \
        -e 's/&/\&amp;/g' \
        -e 's/</\&lt;/g' \
        -e 's/>/\&gt;/g' \
        -e 's/"/\&quot;/g' \
        -e "s/'/\&#39;/g"
}

# Check if docker is available
check_docker_available() {
    command -v docker >/dev/null 2>&1 || die "Docker is not installed or not in PATH."
    docker info >/dev/null 2>&1 || die "Docker is not accessible (is the daemon running?)."
}

# Run SQL inside the container WITHOUT selecting DB (useful for SHOW DATABASES)
run_sql_nodb() {
    local query="$1"
    docker exec -e MYSQL_PWD="$DB_PASS" "$DB_CONTAINER" mariadb -u"$DB_USER" -N -s -e "$query" 2>/dev/null
}

# Run SQL inside the container selecting the configured DB
run_sql() {
    local query="$1"
    docker exec -e MYSQL_PWD="$DB_PASS" "$DB_CONTAINER" mariadb -u"$DB_USER" -D"$DB_NAME" -N -s -e "$query" 2>/dev/null
}

# Validate YYYY-MM-DD date (also checks if date is real)
validate_date() {
    local d="$1"
    [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
    date -d "$d" >/dev/null 2>&1 || return 1
    return 0
}

# Strict username validation to prevent SQL injection
# Allowed: letters, digits, dot, underscore, hyphen
is_valid_username() {
    local u="$1"
    [[ "$u" =~ ^[A-Za-z0-9._-]{1,64}$ ]]
}

# Print guideline for users file
print_users_file_guide() {
    echo -e "${BOLD}[i] Bulk Scan (File) Guide${NC}"
    echo -e "    - The file can be named ${YELLOW}users.txt${NC} and placed next to this script, OR you can provide a custom path."
    echo -e "    - Usernames can be:"
    echo -e "        • One username per line"
    echo -e "        • Or comma-separated on one/multiple lines"
    echo -e "    - Allowed characters per username: ${YELLOW}A-Z a-z 0-9 . _ -${NC}"
    echo -e "    - Examples:"
    echo -e "        ilia"
    echo -e "        admin,hr.manager"
    echo -e "        john.doe"
    echo ""
}

# Load usernames from manual input string (comma-separated)
# Outputs: global USER_ARRAY populated
parse_users_from_string() {
    local raw="$1"
    local token
    local -A seen=()
    USER_ARRAY=()

    IFS=',' read -ra _TOKENS <<< "$raw"
    for token in "${_TOKENS[@]}"; do
        token="$(echo "$token" | xargs)" # trim
        [[ -z "$token" ]] && continue

        if ! is_valid_username "$token"; then
            print_and_log "${YELLOW}[!] Skipping invalid username: '$token' (allowed: A-Z a-z 0-9 . _ -)${NC}"
            continue
        fi

        if [[ -z "${seen[$token]}" ]]; then
            USER_ARRAY+=("$token")
            seen["$token"]=1
        fi
    done
}

# Load usernames from a file (supports line-by-line and comma-separated)
# Outputs: global USER_ARRAY populated
parse_users_from_file() {
    local file_path="$1"
    local content
    content="$(cat "$file_path" 2>/dev/null)"
    content="$(echo "$content" | tr '\n' ',' )" # Normalize: newlines -> commas
    parse_users_from_string "$content"
}

# Check container + mariadb client + DB existence. Exit on failure.
check_database_exists_or_exit() {
    check_docker_available

    docker inspect "$DB_CONTAINER" >/dev/null 2>&1 || die "Container '$DB_CONTAINER' not found."

    local running
    running="$(docker inspect -f '{{.State.Running}}' "$DB_CONTAINER" 2>/dev/null)"
    [[ "$running" == "true" ]] || die "Container '$DB_CONTAINER' is not running."

    docker exec "$DB_CONTAINER" sh -lc 'command -v mariadb >/dev/null 2>&1' || die "mariadb client not found inside container '$DB_CONTAINER'."

    local db_found
    db_found="$(run_sql_nodb "SHOW DATABASES LIKE '$DB_NAME';")"
    [[ "$db_found" == "$DB_NAME" ]] || die "Database '$DB_NAME' does not exist (or user '$DB_USER' has no access)."
}

# Try to install wkhtmltopdf based on OS/package manager
install_wkhtmltopdf() {
    print_and_log "${YELLOW}[!] wkhtmltopdf is required for PDF export.${NC}"

    if [[ "$EUID" -ne 0 ]] && ! command -v sudo >/dev/null 2>&1; then
        print_and_log "${RED}[X] Cannot auto-install wkhtmltopdf (no sudo and not running as root).${NC}"
        print_and_log "${YELLOW}[!] Please install wkhtmltopdf manually, then re-run PDF export.${NC}"
        return 1
    fi

    if command -v apt-get >/dev/null 2>&1; then
        if [[ "$EUID" -ne 0 ]]; then
            sudo apt-get update && sudo apt-get install -y wkhtmltopdf
        else
            apt-get update && apt-get install -y wkhtmltopdf
        fi
        return $?
    fi

    if command -v dnf >/dev/null 2>&1; then
        if [[ "$EUID" -ne 0 ]]; then
            sudo dnf install -y wkhtmltopdf
        else
            dnf install -y wkhtmltopdf
        fi
        return $?
    fi
    if command -v yum >/dev/null 2>&1; then
        if [[ "$EUID" -ne 0 ]]; then
            sudo yum install -y wkhtmltopdf
        else
            yum install -y wkhtmltopdf
        fi
        return $?
    fi

    if command -v pacman >/dev/null 2>&1; then
        if [[ "$EUID" -ne 0 ]]; then
            sudo pacman -Sy --noconfirm wkhtmltopdf
        else
            pacman -Sy --noconfirm wkhtmltopdf
        fi
        return $?
    fi

    if command -v zypper >/dev/null 2>&1; then
        if [[ "$EUID" -ne 0 ]]; then
            sudo zypper --non-interactive install wkhtmltopdf
        else
            zypper --non-interactive install wkhtmltopdf
        fi
        return $?
    fi

    if command -v brew >/dev/null 2>&1; then
        brew install wkhtmltopdf
        return $?
    fi

    print_and_log "${RED}[X] Auto-install is not supported on this system. Please install wkhtmltopdf manually.${NC}"
    return 1
}

# Ensure wkhtmltopdf exists ONLY when PDF export is requested
ensure_wkhtmltopdf_for_pdf() {
    if command -v wkhtmltopdf >/dev/null 2>&1; then
        return 0
    fi

    if confirm_yes_default "    wkhtmltopdf not found. Install now?"; then
        install_wkhtmltopdf || return 1
        command -v wkhtmltopdf >/dev/null 2>&1 || return 1
        print_and_log "${GREEN}[✔] wkhtmltopdf installed successfully.${NC}"
        return 0
    else
        print_and_log "${YELLOW}[!] PDF export skipped (wkhtmltopdf not installed).${NC}"
        return 1
    fi
}

# Convert Gregorian (YYYY-MM-DD) to Jalali (YYYY-MM-DD) using python3 (accurate algorithm, no external libs)
gregorian_to_jalali() {
    local g="$1"
    if ! command -v python3 >/dev/null 2>&1; then
        echo "N/A"
        return 0
    fi

    python3 - <<'PY' "$g"
import sys
g = sys.argv[1]
gy, gm, gd = map(int, g.split('-'))

g_d_m = [0,31,59,90,120,151,181,212,243,273,304,334]
def div(a,b): return a//b

gy2 = gy - 1600
gm2 = gm - 1
gd2 = gd - 1

g_day_no = 365*gy2 + div(gy2+3,4) - div(gy2+99,100) + div(gy2+399,400)
g_day_no += g_d_m[gm2] + gd2
if gm2 > 1 and ((gy%4==0 and gy%100!=0) or (gy%400==0)):
    g_day_no += 1

j_day_no = g_day_no - 79
j_np = div(j_day_no, 12053)
j_day_no %= 12053

jy = 979 + 33*j_np + 4*div(j_day_no, 1461)
j_day_no %= 1461

if j_day_no >= 366:
    jy += div(j_day_no-366, 365)
    j_day_no = (j_day_no-366) % 365

if j_day_no < 186:
    jm = 1 + div(j_day_no, 31)
    jd = 1 + (j_day_no % 31)
else:
    jm = 7 + div(j_day_no-186, 30)
    jd = 1 + ((j_day_no-186) % 30)

print(f"{jy:04d}-{jm:02d}-{jd:02d}")
PY
}

# Export CSV/JSON (includes both Gregorian and Jalali dates)
export_data() {
    local raw_data="$1"   # expected fields: g_date j_date in out hours
    local username="$2"
    local format="$3"
    local default_filename="clockwork_${username}_$(date +%s)"
    local INPUT_FILE filepath

    echo -e "${BOLD}[?] Export Location${NC}"
    read -p "    Enter filename (Default: ./$default_filename.$format): " INPUT_FILE
    filepath=${INPUT_FILE:-"./$default_filename.$format"}

    if [ "$format" == "csv" ]; then
        echo "Date(Gregorian),Date(Persian),Check-in,Check-out,Work Duration (hrs)" > "$filepath"
        echo "$raw_data" | awk '{print $1","$2","$3","$4","$5}' >> "$filepath"
        echo -e "${GREEN}[✔] Exported to $filepath${NC}"

    elif [ "$format" == "json" ]; then
        echo "[" > "$filepath"
        local first=true
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            read -r g j t_in t_out duration <<< "$line"
            if [ "$first" = true ]; then first=false; else echo "," >> "$filepath"; fi
            echo "  { \"date_gregorian\": \"$g\", \"date_persian\": \"$j\", \"check_in\": \"$t_in\", \"check_out\": \"$t_out\", \"work_duration_hours\": \"$duration\" }" >> "$filepath"
        done <<< "$raw_data"
        echo "]" >> "$filepath"
        echo -e "${GREEN}[✔] Exported to $filepath${NC}"
    fi
}

# Export ONE combined PDF for all users (each user starts on a new page)
export_pdf_all() {
    local start_date="$1"
    local end_date="$2"
    shift 2

    ensure_wkhtmltopdf_for_pdf || return 1

    # Persian date range (fallback to Gregorian if Jalali is not available)
    local p_start p_end
    p_start="$(gregorian_to_jalali "$start_date")"
    p_end="$(gregorian_to_jalali "$end_date")"
    if [[ "$p_start" == "N/A" || "$p_end" == "N/A" ]]; then
        p_start="$start_date"
        p_end="$end_date"
    fi

    # Persian generated date (without timezone)
    local g_today p_today time_now generated_at
    g_today="$(date '+%Y-%m-%d')"
    p_today="$(gregorian_to_jalali "$g_today")"
    [[ "$p_today" == "N/A" ]] && p_today="$g_today"
    time_now="$(date '+%H:%M')"
    generated_at="${p_today} ${time_now}"

    # Better default file name mapping (one PDF for all users)
    local ts default_filename INPUT_FILE out_pdf
    ts="$(date +%Y%m%d_%H%M%S)"
    default_filename="clockwork_attendance_${p_start}_to_${p_end}_${ts}.pdf"

    echo -e "${BOLD}[?] Export Location${NC}"
    read -p "    Enter filename (Default: ./$default_filename): " INPUT_FILE
    out_pdf=${INPUT_FILE:-"./$default_filename"}
    [[ "$out_pdf" != *.pdf ]] && out_pdf="${out_pdf}.pdf"

    # Build a single HTML with:
    # - Summary page
    # - One page per user (page-break)
    local tmp_html
    tmp_html="$(mktemp /tmp/clockwork_all_XXXXXX.html)"

    {
        echo '<!doctype html>'
        echo '<html><head><meta charset="utf-8">'
        echo '<title>Clockwork Attendance Report</title>'
        echo '<style>'
        echo 'body{font-family:Arial,Helvetica,sans-serif;font-size:12px;margin:18px;color:#111;}'
        echo '.topbar{height:10px;background:#09A752;border-radius:6px;margin-bottom:12px;}'
        echo 'h1{font-size:20px;margin:0 0 6px 0;color:#09A752;}'
        echo 'h2{font-size:15px;margin:0 0 6px 0;color:#09A752;}'
        echo '.meta{margin-bottom:10px;padding:10px;border:1px solid #ddd;border-radius:6px;background:#fafafa;}'
        echo '.meta div{margin:2px 0;}'
        echo '.badge{display:inline-block;padding:2px 8px;border-radius:999px;font-size:11px;background:#09A752;color:#fff;margin-left:8px;}'
        echo 'table{border-collapse:collapse;width:100%;margin-top:8px;}'
        echo 'th,td{border:1px solid #333;padding:7px 6px;text-align:left;}'
        echo 'th{background:#F58321;color:#FFFFFF;}'
        echo 'tr:nth-child(even) td{background:#f7f7f7;}'
        echo 'td.mono{font-family:Consolas,Menlo,Monaco,monospace;}'
        echo '.totalBox{margin-top:10px;padding:10px;border:1px solid #ddd;border-radius:6px;background:#fff;}'
        echo '.totalBox .label{font-weight:bold;color:#444;}'
        echo '.totalBox .value{font-weight:bold;color:#09A752;font-size:14px;margin-left:6px;}'
        echo '.foot{margin-top:14px;font-size:10px;color:#444;}'
        echo '.page{page-break-after:always;}'
        echo '.watermark{position:fixed;right:18px;top:18px;font-size:10px;color:#999;}'
        echo '</style></head><body>'

        # ------------------------
        # Summary Page
        # ------------------------
        echo '<div class="page">'
        echo '<div class="topbar"></div>'
        echo "<div class='watermark'>Clockwork OrangeHRM CLI</div>"
        echo "<h1>Attendance Report <span class='badge'>OrangeHRM</span></h1>"

        echo '<div class="meta">'
        echo "<div><b>Date Range:</b> $(html_escape "$p_start") to $(html_escape "$p_end")</div>"
        echo "<div><b>Generated:</b> $(html_escape "$generated_at")</div>"
        echo "<div><b>Users:</b> $(html_escape "${#USER_ARRAY[@]}")</div>"
        echo '</div>'

        echo '<h2>Summary</h2>'
        echo '<table>'
        echo '<tr><th>User</th><th>Total Work Duration (hrs)</th><th>Records</th><th>Missing Check-out</th></tr>'

        local u total rec miss
        for u in "${USER_ARRAY[@]}"; do
            total="${TOTAL_BY_USER[$u]:-0.00}"
            rec="${RECORDS_BY_USER[$u]:-0}"
            miss="${MISSING_BY_USER[$u]:-0}"
            echo "<tr><td>$(html_escape "$u")</td><td class='mono'>$(html_escape "$total")</td><td class='mono'>$(html_escape "$rec")</td><td class='mono'>$(html_escape "$miss")</td></tr>"
        done
        echo '</table>'

        echo "<div class='foot'>Generated by Clockwork OrangeHRM CLI</div>"
        echo '</div>'

        # ------------------------
        # One Page Per User
        # ------------------------
        for u in "${USER_ARRAY[@]}"; do
            local data_file
            data_file="$RUN_TMP_DIR/${u}.data"

            # If a user was skipped/not found, no data file will exist; skip it in PDF.
            [[ -f "$data_file" ]] || continue

            total="${TOTAL_BY_USER[$u]:-0.00}"

            echo '<div class="page">'
            echo '<div class="topbar"></div>'
            echo "<div class='watermark'>Clockwork OrangeHRM CLI</div>"
            echo "<h1>Attendance Report <span class='badge'>OrangeHRM</span></h1>"

            echo '<div class="meta">'
            echo "<div><b>User:</b> $(html_escape "$u")</div>"
            echo "<div><b>Date Range:</b> $(html_escape "$p_start") to $(html_escape "$p_end")</div>"
            echo "<div><b>Generated:</b> $(html_escape "$generated_at")</div>"
            echo '</div>'

            echo '<table>'
            echo '<tr><th>Date (Gregorian)</th><th>Date (Persian)</th><th>Check-in</th><th>Check-out</th><th>Work Duration (hrs)</th></tr>'

            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                read -r g j t_in t_out duration <<< "$line"
                echo "<tr><td class='mono'>$(html_escape "$g")</td><td class='mono'>$(html_escape "$j")</td><td class='mono'>$(html_escape "$t_in")</td><td class='mono'>$(html_escape "$t_out")</td><td class='mono'>$(html_escape "$duration")</td></tr>"
            done < "$data_file"

            echo '</table>'
            echo "<div class='totalBox'><span class='label'>TOTAL WORK DURATION (HRS):</span><span class='value'>$(html_escape "$total")</span></div>"
            echo "<div class='foot'>Generated by Clockwork OrangeHRM CLI</div>"
            echo '</div>'
        done

        # No trailing page-break needed; harmless if present.
        echo '</body></html>'
    } > "$tmp_html"

    # Convert to PDF (add a professional footer with page numbers)
    wkhtmltopdf --encoding utf-8 --page-size A4 \
        --margin-top 12 --margin-bottom 14 --margin-left 10 --margin-right 10 \
        --footer-right "Page [page] / [toPage]" --footer-font-size 8 --footer-spacing 6 \
        "$tmp_html" "$out_pdf" >/dev/null 2>&1

    local rc=$?
    rm -f "$tmp_html"

    if [[ $rc -ne 0 ]]; then
        print_and_log "${RED}[X] PDF generation failed. (wkhtmltopdf returned error)${NC}"
        return 1
    fi

    print_and_log "${GREEN}[✔] Exported to $out_pdf${NC}"
    return 0
}

# --- Initialization ---
clear
echo -e "${YELLOW}${BOLD}"
cat << "EOF"
 ██████╗██╗      ██████╗ ██████╗██╗  ██╗██╗     ██╗ ██████╗ ██████╗ ██╗  ██╗
██╔════╝██║     ██╔═══██╗██╔════╝██║ ██╔╝██║     ██║██╔═══██╗██╔══██╗██║ ██╔╝
██║     ██║     ██║   ██║██║     █████╔╝ ██║ █╗ ██║██║   ██║██████╔╝█████╔╝ 
██║     ██║     ██║   ██║██║     ██╔═██╗ ██║███╗██║██║   ██║██╔══██╗██╔═██╗ 
╚██████╗███████╗╚██████╔╝╚██████╗██║  ██╗╚███╔███╔╝╚██████╔╝██║  ██║██║  ██╗
 ╚═════╝╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝ ╚══╝╚══╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝
EOF
echo -e "${NC}"
print_and_log ":: Session Started at $(date) ::"
echo ""

# Load Env
if [ -f .env ]; then
    echo -e "${GREEN}[+] Configuration loaded from .env${NC}"
    export $(grep -v '^#' .env | xargs)
else
    echo -e "${YELLOW}[!] No .env file found. Running in interactive mode.${NC}"
fi

if [ -z "$DB_PASS" ]; then
    echo -n "Enter MariaDB Password: "
    read -s DB_PASS
    echo ""
fi

# ==============================================================================
# MAIN LOOP
# ==============================================================================

while true; do
    echo -e "\n${CYAN}========================================================${NC}"

    # Create a temp directory for this run (used for combined PDF)
    RUN_TMP_DIR="$(mktemp -d /tmp/clockwork_run_XXXXXX)"
    # Associative arrays for summary metrics (Bash 4+)
    declare -A TOTAL_BY_USER
    declare -A RECORDS_BY_USER
    declare -A MISSING_BY_USER

    # 0) Mode Selection (Manual vs File Scan)
    echo -e "${BOLD}[?] Input Mode${NC}"
    echo "    1) Manual usernames (Default)"
    echo "    2) File scan (bulk via users.txt)"
    read -p "    Select option [1]: " MODE_OPT
    MODE_OPT=${MODE_OPT:-1}

    USER_ARRAY=()

    if [[ "$MODE_OPT" -eq 2 ]]; then
        echo ""
        print_users_file_guide

        local_file="$DEFAULT_USERS_FILE"

        if [[ -f "$local_file" ]]; then
            echo -e "${GREEN}[✔] Found users file next to script:${NC} $local_file"
            if ! confirm_yes_default "    Use this file?"; then
                local_file=""
            fi
        else
            echo -e "${YELLOW}[!] users.txt not found next to the script.${NC}"
            local_file=""
        fi

        while [[ -z "$local_file" ]]; do
            read -p "    Enter path to users file: " INPUT_PATH
            INPUT_PATH="$(expand_tilde "$INPUT_PATH")"
            if [[ -f "$INPUT_PATH" ]]; then
                echo -e "${GREEN}[✔] File found:${NC} $INPUT_PATH"
                if confirm_yes_default "    Scan this file?"; then
                    local_file="$INPUT_PATH"
                else
                    echo -e "${YELLOW}[!] Okay. Provide another path.${NC}"
                fi
            else
                echo -e "${RED}[X] File not found: $INPUT_PATH${NC}"
            fi
        done

        parse_users_from_file "$local_file"

        if [[ "${#USER_ARRAY[@]}" -eq 0 ]]; then
            echo -e "${RED}[X] No valid usernames found in the file. Switching back to manual mode.${NC}"
            MODE_OPT=1
        else
            echo -e "${GREEN}[✔] Loaded ${#USER_ARRAY[@]} user(s) for scanning.${NC}"
        fi
    fi

    if [[ "$MODE_OPT" -eq 1 ]]; then
        CURRENT_USER="$(whoami)"
        echo -e "${BOLD}[?] Target Username(s)${NC}"
        echo -e "    ${YELLOW}Tip: Separate multiple users with comma (e.g. ilia,admin)${NC}"
        read -p "    Enter username(s) (Default: $CURRENT_USER): " INPUT_USER
        RAW_USERS=${INPUT_USER:-$CURRENT_USER}
        parse_users_from_string "$RAW_USERS"

        if [[ "${#USER_ARRAY[@]}" -eq 0 ]]; then
            echo -e "${RED}[X] No valid usernames provided. Try again.${NC}"
            cleanup
            continue
        fi
    fi

    # 1) Date Range
    echo -e "\n${BOLD}[?] Date Selection${NC}"
    echo "    1) Current Month (Default)"
    echo "    2) Custom Range"
    read -p "    Select option [1]: " DATE_OPT
    DATE_OPT=${DATE_OPT:-1}

    if [ "$DATE_OPT" -eq 1 ]; then
        START_DATE=$(date +%Y-%m-01)
        END_DATE=$(date +%Y-%m-%d)
        print_and_log "[Config] Date Range: Current Month ($START_DATE to $END_DATE)"
    else
        while true; do
            read -p "    Enter Start Date (YYYY-MM-DD): " START_DATE_INPUT
            validate_date "$START_DATE_INPUT" && break
            echo -e "${RED}[X] Invalid date. Please use YYYY-MM-DD.${NC}"
        done

        TODAY=$(date +%Y-%m-%d)
        while true; do
            read -p "    Enter End Date   (YYYY-MM-DD) [Default: $TODAY]: " END_DATE_INPUT
            END_DATE_INPUT=${END_DATE_INPUT:-$TODAY}
            validate_date "$END_DATE_INPUT" && break
            echo -e "${RED}[X] Invalid date. Please use YYYY-MM-DD.${NC}"
        done

        START_DATE="$START_DATE_INPUT"
        END_DATE="$END_DATE_INPUT"
        unset START_DATE_INPUT END_DATE_INPUT
        print_and_log "[Config] Date Range: Custom ($START_DATE to $END_DATE)"
    fi

    # 2) Database existence check (required)
    echo -e "\n${YELLOW}[*] Connecting to container '$DB_CONTAINER'...${NC}"
    check_database_exists_or_exit
    echo -e "${GREEN}[✔] Database '$DB_NAME' found and accessible.${NC}"

    # 3) Process Each User
    for USERNAME in "${USER_ARRAY[@]}"; do
        print_and_log "\n--- Report for: $USERNAME ---"

        EMP_ID=$(run_sql "SELECT emp_number FROM ohrm_user WHERE user_name = '$USERNAME';")

        if [ -z "$EMP_ID" ] || [ "$EMP_ID" == "NULL" ]; then
            print_and_log "${RED}[X] User '$USERNAME' not found! Skipping...${NC}"
            continue
        fi

        RAW_SQL_DATA=$(run_sql "SELECT CONCAT(DATE(punch_in_user_time), ' ', TIME_FORMAT(punch_in_user_time, '%H:%i'), ' ', COALESCE(TIME_FORMAT(punch_out_user_time, '%H:%i'), '??:??'), ' ', COALESCE(ROUND(TIMESTAMPDIFF(MINUTE, punch_in_user_time, punch_out_user_time)/60, 2), 0)) FROM ohrm_attendance_record WHERE employee_id = $EMP_ID AND DATE(punch_in_user_time) BETWEEN '$START_DATE' AND '$END_DATE' ORDER BY punch_in_user_time;")

        TOTAL_HOURS=$(run_sql "SELECT ROUND(SUM(TIMESTAMPDIFF(MINUTE, punch_in_user_time, punch_out_user_time)) / 60, 2) FROM ohrm_attendance_record WHERE employee_id = $EMP_ID AND DATE(punch_in_user_time) BETWEEN '$START_DATE' AND '$END_DATE';")
        TOTAL_HOURS=${TOTAL_HOURS:-"0.00"}

        # Enrich data with Persian date and store to per-user file for combined PDF
        user_data_file="$RUN_TMP_DIR/${USERNAME}.data"
        : > "$user_data_file"

        records=0
        missing=0

        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            read -r g t_in t_out duration <<< "$line"
            j="$(gregorian_to_jalali "$g")"
            echo "${g} ${j} ${t_in} ${t_out} ${duration}" >> "$user_data_file"

            records=$((records + 1))
            [[ "$t_out" == "??:??" ]] && missing=$((missing + 1))
        done <<< "$RAW_SQL_DATA"

        TOTAL_BY_USER["$USERNAME"]="$TOTAL_HOURS"
        RECORDS_BY_USER["$USERNAME"]="$records"
        MISSING_BY_USER["$USERNAME"]="$missing"

        # Print Table (Gregorian + Persian) to terminal/log
        print_and_log "Date(G)     | Date(P)     | In       | Out      | Hours"
        print_and_log "------------+-------------+----------+----------+-------"
        while IFS= read -r row; do
            [[ -z "$row" ]] && continue
            read -r g j t_in t_out duration <<< "$row"
            FORMATTED_ROW=$(printf "%-10s | %-11s | %-8s | %-8s | %-10s" "$g" "$j" "$t_in" "$t_out" "$duration")
            print_and_log "$FORMATTED_ROW"
        done < "$user_data_file"
        print_and_log "------------+-------------+----------+----------+-------"
        print_and_log "${BOLD}TOTAL HOURS: ${GREEN}$TOTAL_HOURS${NC}"

        # Optional: per-user JSON/CSV export (PDF is handled once at the end as a single combined PDF)
        echo -e "\n${BOLD}[?] Export data for $USERNAME?${NC}"
        echo "    1) No (Default)"
        echo "    2) JSON"
        echo "    3) CSV"
        read -p "    Select option: " EXPORT_OPT

        case $EXPORT_OPT in
            2) export_data "$(cat "$user_data_file")" "$USERNAME" "json" ;;
            3) export_data "$(cat "$user_data_file")" "$USERNAME" "csv" ;;
            *) echo "    Skipping export." ;;
        esac
    done

    # 4) Combined PDF export (one file, one page per user)
    echo -e "\n${BOLD}[?] Export a single PDF report for ALL users in this run?${NC}"
    echo "    1) No (Default)"
    echo "    2) PDF (Combined, one page per user)"
    read -p "    Select option: " PDF_ALL_OPT
    case $PDF_ALL_OPT in
        2) export_pdf_all "$START_DATE" "$END_DATE" ;;
        *) echo "    Skipping combined PDF export." ;;
    esac

    # 5) Loop Decision
    echo -e "\n${CYAN}========================================================${NC}"
    read -p "Do you want to run another query? (y/n) [y]: " RESTART_OPT
    if [[ "$RESTART_OPT" == "n" || "$RESTART_OPT" == "N" ]]; then
        print_and_log ":: Session Ended ::"
        echo -e "${GREEN}Goodbye!${NC}"
        cleanup
        break
    else
        echo -e "${GREEN}Restarting...${NC}"
        cleanup
    fi
done
