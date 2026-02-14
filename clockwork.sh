#!/bin/bash

# ==============================================================================
# Project:     Clockwork OrangeHRM CLI
# Description: Interactive CLI tool to extract work hours from OrangeHRM MariaDB.
# Author:      Ilia Shakeri
# License:     MIT
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

# --- Clear Screen ---
clear

# --- ASCII Banner ---
echo -e "${YELLOW}${BOLD}"
cat << "EOF"
   ____ _            _                     _    
  / ___| | ___   ___| | _____      ___  __| | __
 | |   | |/ _ \ / __| |/ /\ \ /\ / / _ \/ _` |
 | |___| | (_) | (__|   <  \ V  V / (_) \__  |
  \____|_|\___/ \___|_|\_\  \_/\_/ \___/|___/ 
      ORANGEHRM CLI EDITION  v1.0.0
EOF
echo -e "${NC}"
echo -e "${CYAN}:: Time Tracking Extraction Tool ::${NC}"
echo ""

# --- Step 1: Authentication & Config Loading ---
if [ -f .env ]; then
    echo -e "${GREEN}[+] Configuration loaded from .env${NC}"
    export $(grep -v '^#' .env | xargs)
else
    echo -e "${YELLOW}[!] No .env file found. Running in interactive mode.${NC}"
fi

# If password is not set in .env, ask for it
if [ -z "$DB_PASS" ]; then
    echo -n "Enter MariaDB Password: "
    read -s DB_PASS
    echo ""
fi

# --- Step 2: Interactive Inputs ---

# 2.1 Get Username
CURRENT_USER=$(whoami)
echo -e "\n${BOLD}[?] Target Username${NC}"
read -p "    Enter username (Default: $CURRENT_USER): " INPUT_USER
USERNAME=${INPUT_USER:-$CURRENT_USER}

# 2.2 Get Date Range
echo -e "\n${BOLD}[?] Date Selection${NC}"
echo "    1) Current Month (Default)"
echo "    2) Custom Range"
read -p "    Select option [1]: " DATE_OPT
DATE_OPT=${DATE_OPT:-1}

if [ "$DATE_OPT" -eq 1 ]; then
    START_DATE=$(date +%Y-%m-01)
    END_DATE=$(date +%Y-%m-%d)
    echo -e "    ${BLUE}Selected Range: $START_DATE to $END_DATE${NC}"
else
    read -p "    Enter Start Date (YYYY-MM-DD): " START_DATE
    read -p "    Enter End Date   (YYYY-MM-DD): " END_DATE
fi

# 2.3 Get Report Type
echo -e "\n${BOLD}[?] Report Format${NC}"
echo "    1) Summary Only (Total Hours) (Default)"
echo "    2) Detailed Table (Daily Logs)"
read -p "    Select option [1]: " REPORT_OPT
REPORT_OPT=${REPORT_OPT:-1}

# --- Step 3: Execution ---

echo -e "\n${YELLOW}[*] Connecting to container '$DB_CONTAINER'...${NC}"

# Helper function to run SQL securely
run_sql() {
    local query="$1"
    docker exec "$DB_CONTAINER" mariadb -u"$DB_USER" -p"$DB_PASS" -D"$DB_NAME" -N -s -e "$query" 2>/dev/null
}

# 3.1 Fetch Employee ID
EMP_ID=$(run_sql "SELECT emp_number FROM ohrm_user WHERE user_name = '$USERNAME';")

if [ -z "$EMP_ID" ] || [ "$EMP_ID" == "NULL" ]; then
    echo -e "${RED}[X] Error: User '$USERNAME' not found in database!${NC}"
    echo -e "${RED}    Check if the username is correct or if the container is running.${NC}"
    exit 1
fi

echo -e "${GREEN}[+] User verified! Employee ID: $EMP_ID${NC}"
echo -e "${CYAN}--------------------------------------------------------${NC}"

# 3.2 Fetch Data based on Report Type
if [ "$REPORT_OPT" -eq 2 ]; then
    # DETAILED TABLE HEADERS
    printf "${BOLD}%-12s | %-8s | %-8s | %-10s${NC}\n" "Date" "In" "Out" "Hours"
    echo "------------------------------------------------"
    
    # DETAILED QUERY
    RAW_DATA=$(run_sql "SELECT CONCAT(DATE(punch_in_user_time), ' ', TIME_FORMAT(punch_in_user_time, '%H:%i'), ' ', COALESCE(TIME_FORMAT(punch_out_user_time, '%H:%i'), '??:??'), ' ', COALESCE(ROUND(TIMESTAMPDIFF(MINUTE, punch_in_user_time, punch_out_user_time)/60, 2), 0)) FROM ohrm_attendance_record WHERE employee_id = $EMP_ID AND DATE(punch_in_user_time) BETWEEN '$START_DATE' AND '$END_DATE';")
    
    # Process line by line
    while IFS= read -r line; do
        if [ ! -z "$line" ]; then
            read -r d t_in t_out duration <<< "$line"
            printf "%-12s | %-8s | %-8s | %-10s\n" "$d" "$t_in" "$t_out" "$duration"
        fi
    done <<< "$RAW_DATA"
    
    echo "------------------------------------------------"
fi

# 3.3 Calculate Total Sum (Always shown)
TOTAL_HOURS=$(run_sql "SELECT ROUND(SUM(TIMESTAMPDIFF(MINUTE, punch_in_user_time, punch_out_user_time)) / 60, 2) FROM ohrm_attendance_record WHERE employee_id = $EMP_ID AND DATE(punch_in_user_time) BETWEEN '$START_DATE' AND '$END_DATE';")

# Handle NULL
if [ -z "$TOTAL_HOURS" ] || [ "$TOTAL_HOURS" == "NULL" ]; then
    TOTAL_HOURS="0.00"
fi

echo -e "${BOLD}TOTAL WORK HOURS (${START_DATE} to ${END_DATE}): ${GREEN}${TOTAL_HOURS}${NC}"
echo -e "${CYAN}========================================================${NC}"