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

# --- Trap Ctrl+C for clean exit ---
trap "echo -e '\n${YELLOW}[!] Exiting...${NC}'; exit 0" SIGINT

# --- Helper Functions ---

# Function to write to log file without colors
log_entry() {
    local message="$1"
    # Create logs directory if not exists
    mkdir -p "$LOG_DIR"
    local today_log="$LOG_DIR/$(date +%Y-%m-%d).log"
    
    # Strip ANSI color codes using sed and append to file
    echo -e "$message" | sed 's/\x1b\[[0-9;]*m//g' >> "$today_log"
}

# Wrapper to print to screen AND log file
print_and_log() {
    echo -e "$1"
    log_entry "$1"
}

run_sql() {
    local query="$1"
    docker exec "$DB_CONTAINER" mariadb -u"$DB_USER" -p"$DB_PASS" -D"$DB_NAME" -N -s -e "$query" 2>/dev/null
}

export_data() {
    local raw_data="$1"
    local username="$2"
    local format="$3"
    local default_filename="clockwork_${username}_$(date +%s)"
    
    echo -e "${BOLD}[?] Export Location${NC}"
    read -p "    Enter filename (Default: ./$default_filename.$format): " INPUT_FILE
    local filepath=${INPUT_FILE:-"./$default_filename.$format"}

    if [ "$format" == "csv" ]; then
        echo "Date,Punch In,Punch Out,Hours" > "$filepath"
        # Convert pipe separators to commas
        echo "$raw_data" | awk '{print $1","$2","$3","$4}' >> "$filepath"
        echo -e "${GREEN}[✔] Exported to $filepath${NC}"
        
    elif [ "$format" == "json" ]; then
        # Construct simplified JSON manually
        echo "[" > "$filepath"
        local first=true
        while read -r line; do
            if [ ! -z "$line" ]; then
                read -r d t_in t_out duration <<< "$line"
                if [ "$first" = true ]; then first=false; else echo "," >> "$filepath"; fi
                echo "  { \"date\": \"$d\", \"in\": \"$t_in\", \"out\": \"$t_out\", \"hours\": \"$duration\" }" >> "$filepath"
            fi
        done <<< "$raw_data"
        echo "]" >> "$filepath"
        echo -e "${GREEN}[✔] Exported to $filepath${NC}"
    fi
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
    
    # 1. Get Usernames (Comma Separated)
    CURRENT_USER=$(whoami)
    echo -e "${BOLD}[?] Target Username(s)${NC}"
    echo -e "    ${YELLOW}Tip: Separate multiple users with comma (e.g. ilia,admin)${NC}"
    read -p "    Enter username(s) (Default: $CURRENT_USER): " INPUT_USER
    RAW_USERS=${INPUT_USER:-$CURRENT_USER}

    # Split into array
    IFS=',' read -ra USER_ARRAY <<< "$RAW_USERS"

    # 2. Get Date Range
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
        while [[ -z "$START_DATE_INPUT" ]]; do
            read -p "    Enter Start Date (YYYY-MM-DD): " START_DATE_INPUT
        done
        TODAY=$(date +%Y-%m-%d)
        read -p "    Enter End Date   (YYYY-MM-DD) [Default: $TODAY]: " END_DATE_INPUT
        START_DATE=$START_DATE_INPUT
        END_DATE=${END_DATE_INPUT:-$TODAY}
        
        # Reset input vars for next loop
        unset START_DATE_INPUT END_DATE_INPUT 
        print_and_log "[Config] Date Range: Custom ($START_DATE to $END_DATE)"
    fi

    # 3. Process Each User
    echo -e "\n${YELLOW}[*] Connecting to container '$DB_CONTAINER'...${NC}"

    for RAW_USER in "${USER_ARRAY[@]}"; do
        # Trim whitespace
        USERNAME=$(echo "$RAW_USER" | xargs)
        
        print_and_log "\n--- Report for: $USERNAME ---"

        # Get EMP ID
        EMP_ID=$(run_sql "SELECT emp_number FROM ohrm_user WHERE user_name = '$USERNAME';")

        if [ -z "$EMP_ID" ] || [ "$EMP_ID" == "NULL" ]; then
            print_and_log "${RED}[X] User '$USERNAME' not found! Skipping...${NC}"
            continue
        fi

        # Get Raw Data
        RAW_DATA=$(run_sql "SELECT CONCAT(DATE(punch_in_user_time), ' ', TIME_FORMAT(punch_in_user_time, '%H:%i'), ' ', COALESCE(TIME_FORMAT(punch_out_user_time, '%H:%i'), '??:??'), ' ', COALESCE(ROUND(TIMESTAMPDIFF(MINUTE, punch_in_user_time, punch_out_user_time)/60, 2), 0)) FROM ohrm_attendance_record WHERE employee_id = $EMP_ID AND DATE(punch_in_user_time) BETWEEN '$START_DATE' AND '$END_DATE';")

        # Get Total
        TOTAL_HOURS=$(run_sql "SELECT ROUND(SUM(TIMESTAMPDIFF(MINUTE, punch_in_user_time, punch_out_user_time)) / 60, 2) FROM ohrm_attendance_record WHERE employee_id = $EMP_ID AND DATE(punch_in_user_time) BETWEEN '$START_DATE' AND '$END_DATE';")
        TOTAL_HOURS=${TOTAL_HOURS:-"0.00"}

        # Print Table
        print_and_log "Date         | In       | Out      | Hours"
        print_and_log "-------------+----------+----------+-------"
        
        # We assume RAW_DATA lines are space separated based on query
        while IFS= read -r line; do
            if [ ! -z "$line" ]; then
                read -r d t_in t_out duration <<< "$line"
                # Use printf for alignment in logs and screen
                FORMATTED_ROW=$(printf "%-12s | %-8s | %-8s | %-10s" "$d" "$t_in" "$t_out" "$duration")
                print_and_log "$FORMATTED_ROW"
            fi
        done <<< "$RAW_DATA"
        
        print_and_log "-------------+----------+----------+-------"
        print_and_log "${BOLD}TOTAL HOURS: ${GREEN}$TOTAL_HOURS${NC}"
        
        # 4. Export Prompt (Per User)
        echo -e "\n${BOLD}[?] Export data for $USERNAME?${NC}"
        echo "    1) No (Default)"
        echo "    2) JSON"
        echo "    3) CSV"
        read -p "    Select option: " EXPORT_OPT
        
        case $EXPORT_OPT in
            2) export_data "$RAW_DATA" "$USERNAME" "json" ;;
            3) export_data "$RAW_DATA" "$USERNAME" "csv" ;;
            *) echo "    Skipping export." ;;
        esac
    done

    # 5. Loop Decision
    echo -e "\n${CYAN}========================================================${NC}"
    read -p "Do you want to run another query? (y/n) [y]: " RESTART_OPT
    if [[ "$RESTART_OPT" == "n" || "$RESTART_OPT" == "N" ]]; then
        print_and_log ":: Session Ended ::"
        echo -e "${GREEN}Goodbye!${NC}"
        break
    else
        echo -e "${GREEN}Restarting...${NC}"
        # Variables will be overwritten in next loop
    fi
done