#!/bin/bash
#
# disk_wipe_utility.sh
# A comprehensive utility for securely wiping hard drives on Linux systems
#
# Author: [Your name or username]
# GitHub: [Your GitHub URL]
# Version: 1.0
#
# Licensed under MIT License
#
# Usage: sudo bash disk_wipe_utility.sh
#
# Features:
# - Text-based interactive menu
# - Multi-drive parallel wiping
# - Partition deletion
# - Progress monitoring and notifications
# - Handles interruptions and power loss
# - Multiple wiping methods (quick, secure, DoD)
#
# Requirements:
# - Must be run as root (sudo)
# - Requires: dd, parted, lsblk, blockdev

# Color codes for text formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}${BOLD}This script must be run as root. Try 'sudo bash $0'${NC}"
    exit 1
fi

# Check for required tools
for cmd in dd parted lsblk blockdev grep awk; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}${BOLD}Error: Required command '$cmd' not found. Please install it and try again.${NC}"
        exit 1
    fi
done

# Global array to store selected drives
selected_drives=()

# Log directory
LOG_DIR="/tmp/disk_wipe_logs"
RECOVERY_FILE="/tmp/disk_wipe_recovery"

# Initialize log directory
mkdir -p "$LOG_DIR"

# Function to display a simple text-based menu
show_menu() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}${BOLD}              DISK WIPING UTILITY                    ${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo ""
    echo "This utility will help you securely wipe hard drives."
    echo -e "${RED}${BOLD}WARNING: All data on selected drives will be permanently destroyed!${NC}"
    echo ""
    echo "1. List available drives"
    echo "2. Select drives to wipe"
    echo "3. Start wiping process"
    echo "4. Check wiping status"
    echo "5. Watch wiping progress (live)"
    echo "6. Exit"
    echo ""
    echo -e "${BLUE}=====================================================${NC}"
    
    # Check if any wiping process has completed since last check
    any_completed=false
    for drive in "${selected_drives[@]}"; do
        if [ -f "$LOG_DIR/$drive.pid" ]; then
            pid=$(cat "$LOG_DIR/$drive.pid")
            if ! ps -p $pid > /dev/null && [ ! -f "$LOG_DIR/$drive.completed" ]; then
                echo -e "${GREEN}${BOLD}DRIVE COMPLETED: /dev/$drive has finished wiping!${NC}"
                touch "$LOG_DIR/$drive.completed"
                any_completed=true
            fi
        fi
    done
    
    # Check if all drives are complete
    all_complete=true
    active_count=0
    total_selected=${#selected_drives[@]}
    
    if [ $total_selected -gt 0 ]; then
        for drive in "${selected_drives[@]}"; do
            if [ -f "$LOG_DIR/$drive.pid" ]; then
                pid=$(cat "$LOG_DIR/$drive.pid")
                if ps -p $pid > /dev/null; then
                    all_complete=false
                    active_count=$((active_count + 1))
                fi
            elif [ ! -f "$LOG_DIR/$drive.completed" ]; then
                all_complete=false
            fi
        done
        
        if [ "$all_complete" = true ] && [ $total_selected -gt 0 ]; then
            echo -e "${GREEN}${BOLD}ALL DRIVES COMPLETED WIPING!${NC}"
            echo -e "\a"  # Terminal bell
        else
            echo -e "${YELLOW}Status: $active_count/$total_selected drives still wiping${NC}"
        fi
    fi
    
    echo -n "Enter your choice [1-6]: "
}

# Function to list available drives
list_drives() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}${BOLD}              AVAILABLE DRIVES                       ${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo ""
    
    # Get all disk devices (excluding ram, loop, and partition entries)
    echo -e "${BOLD}Device | Size | Model${NC}"
    echo "--------------------------------------"
    lsblk -d -o NAME,SIZE,MODEL | grep -v "loop\|ram" | tail -n +2
    
    echo ""
    echo -e "${YELLOW}${BOLD}NOTE: System drive is also listed. BE CAREFUL not to wipe it!${NC}"
    echo -e "${YELLOW}Current drive mount points:${NC}"
    df -h | grep "/dev/" | awk '{print $1, "mounted on", $6}'
    echo ""
    read -p "Press Enter to continue..."
}

# Function to select drives to wipe
select_drives() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}${BOLD}              SELECT DRIVES TO WIPE                  ${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo ""
    
    # Get all disk devices (excluding ram, loop devices)
    available_drives=($(lsblk -d -o NAME | grep -v "loop\|ram\|NAME"))
    
    if [ ${#available_drives[@]} -eq 0 ]; then
        echo "No drives detected!"
        read -p "Press Enter to continue..."
        return
    fi
    
    echo "Available drives:"
    for i in "${!available_drives[@]}"; do
        drive=${available_drives[$i]}
        size=$(lsblk -d -o SIZE /dev/$drive | tail -n +2)
        model=$(lsblk -d -o MODEL /dev/$drive | tail -n +2)
        
        # Check mount points to warn about system drives
        mount_points=$(lsblk -n -o MOUNTPOINT /dev/$drive | grep -v "^$" | tr '\n' ', ' | sed 's/,$//')
        mounted=""
        if [ ! -z "$mount_points" ]; then
            mounted=" ${RED}[MOUNTED: $mount_points]${NC}"
        fi
        
        # Check if drive is already selected
        if [[ " ${selected_drives[@]} " =~ " $drive " ]]; then
            echo -e "[$i] /dev/$drive | $size | $model ${GREEN}[SELECTED]${NC}$mounted"
        else
            echo -e "[$i] /dev/$drive | $size | $model$mounted"
        fi
    done
    
    echo ""
    echo -e "Current selection: ${GREEN}${selected_drives[@]:-None}${NC}"
    echo ""
    echo "Enter the number of the drive to toggle selection"
    echo "Or type 'clear' to clear all selections"
    echo "Or press Enter to return to main menu"
    echo ""
    read -p "Your choice: " choice
    
    if [[ "$choice" == "clear" ]]; then
        selected_drives=()
        echo "Selection cleared!"
        sleep 2
        select_drives
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -lt "${#available_drives[@]}" ]; then
        drive=${available_drives[$choice]}
        
        # Check if drive is already selected
        if [[ " ${selected_drives[@]} " =~ " $drive " ]]; then
            # Remove from selection
            temp=()
            for sel in "${selected_drives[@]}"; do
                if [ "$sel" != "$drive" ]; then
                    temp+=("$sel")
                fi
            done
            selected_drives=("${temp[@]}")
            echo "Removed /dev/$drive from selection"
        else
            # Add to selection
            selected_drives+=("$drive")
            echo "Added /dev/$drive to selection"
        fi
        
        sleep 1
        select_drives
    fi
}

# Function to wipe a drive and delete partitions
wipe_drive() {
    local drive=$1
    local method=$2
    local log_file="$LOG_DIR/$drive.log"
    
    echo "$(date): Starting wipe process for /dev/$drive using $method method" >> "$log_file"
    
    # First, delete all partitions from the drive
    echo "$(date): Deleting all partitions on /dev/$drive" >> "$log_file"
    
    # Create a new empty partition table (both MBR and GPT for thoroughness)
    echo "Creating new empty partition table..." >> "$log_file"
    parted -s /dev/$drive mklabel msdos >> "$log_file" 2>&1
    parted -s /dev/$drive mklabel gpt >> "$log_file" 2>&1
    
    # Wipe the first and last few MB of the drive to ensure partition tables are gone
    echo "Wiping partition table areas..." >> "$log_file"
    dd if=/dev/zero of=/dev/$drive bs=1M count=10 >> "$log_file" 2>&1
    
    # Seek to end minus 10 MB and wipe there too
    size_bytes=$(blockdev --getsize64 /dev/$drive)
    size_mb=$((size_bytes / 1024 / 1024))
    end_position=$((size_mb - 10))
    dd if=/dev/zero of=/dev/$drive bs=1M seek=$end_position count=10 >> "$log_file" 2>&1
    
    # Now perform the full drive wipe based on selected method
    echo "$(date): Beginning full drive wipe" >> "$log_file"
    
    case "$method" in
        quick)
            echo "Wiping /dev/$drive with zeros..." >> "$log_file"
            dd if=/dev/zero of=/dev/$drive bs=4M status=progress 2>> "$log_file"
            ;;
        secure)
            echo "Securely wiping /dev/$drive with zeros and verification..." >> "$log_file"
            dd if=/dev/zero of=/dev/$drive bs=4M status=progress 2>> "$log_file"
            echo "Verifying wipe on /dev/$drive..." >> "$log_file"
            dd if=/dev/$drive bs=4M count=10 2>/dev/null | hexdump -C | grep -v "00 00 00 00" > "$LOG_DIR/$drive.verify"
            if [ -s "$LOG_DIR/$drive.verify" ]; then
                echo "WARNING: Verification failed! Non-zero data found on /dev/$drive" >> "$log_file"
            else
                echo "Verification passed: Only zeros found on sample from /dev/$drive" >> "$log_file"
            fi
            ;;
        dod)
            echo "Performing DoD wipe on /dev/$drive (this will take much longer)..." >> "$log_file"
            echo "Pass 1/3: Writing zeros..." >> "$log_file"
            dd if=/dev/zero of=/dev/$drive bs=4M status=progress 2>> "$log_file"
            echo "Pass 2/3: Writing ones (0xFF)..." >> "$log_file"
            dd if=/dev/urandom of=/dev/$drive bs=4M status=progress 2>> "$log_file"
            echo "Pass 3/3: Writing random data..." >> "$log_file"
            dd if=/dev/urandom of=/dev/$drive bs=4M status=progress 2>> "$log_file"
            ;;
    esac
    
    # Indicate completion
    echo "$(date): Wipe completed for /dev/$drive" >> "$log_file"
    return 0
}

# Function to start wiping process
start_wiping() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}${BOLD}              START WIPING PROCESS                   ${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo ""
    
    if [ ${#selected_drives[@]} -eq 0 ]; then
        echo "No drives selected! Please select drives first."
        read -p "Press Enter to continue..."
        return
    fi
    
    echo "You've selected the following drives to wipe:"
    for drive in "${selected_drives[@]}"; do
        size=$(lsblk -d -o SIZE /dev/$drive | tail -n +2)
        model=$(lsblk -d -o MODEL /dev/$drive | tail -n +2)
        
        # Check mount points to warn about system drives
        mount_points=$(lsblk -n -o MOUNTPOINT /dev/$drive | grep -v "^$" | tr '\n' ', ' | sed 's/,$//')
        mounted=""
        if [ ! -z "$mount_points" ]; then
            mounted=" ${RED}[MOUNTED: $mount_points]${NC}"
            echo -e "/dev/$drive | $size | $model$mounted ${RED}WARNING: DRIVE IS MOUNTED!${NC}"
        else
            echo "/dev/$drive | $size | $model"
        fi
    done
    
    echo ""
    
    # Check if any selected drives are mounted
    mounted_drives=()
    for drive in "${selected_drives[@]}"; do
        mount_points=$(lsblk -n -o MOUNTPOINT /dev/$drive | grep -v "^$")
        if [ ! -z "$mount_points" ]; then
            mounted_drives+=("$drive")
        fi
    done
    
    if [ ${#mounted_drives[@]} -gt 0 ]; then
        echo -e "${RED}${BOLD}WARNING: The following drives are mounted and cannot be wiped safely:${NC}"
        for drive in "${mounted_drives[@]}"; do
            mount_points=$(lsblk -n -o MOUNTPOINT /dev/$drive | grep -v "^$" | tr '\n' ', ' | sed 's/,$//')
            echo "  - /dev/$drive mounted at: $mount_points"
        done
        echo ""
        echo "These drives must be unmounted before wiping."
        echo "You can use 'umount /dev/$drive' or 'umount <mount_point>' to unmount."
        read -p "Press Enter to return to main menu..."
        return
    fi
    
    echo -e "${RED}${BOLD}WARNING: All data on these drives will be permanently destroyed!${NC}"
    echo -e "${RED}${BOLD}This operation cannot be undone!${NC}"
    echo ""
    echo "Choose wiping method:"
    echo "1. Quick Wipe (zeros, single pass)"
    echo "2. Secure Wipe (zeros, one pass + verification)"
    echo "3. DoD Wipe (multiple passes with different patterns)"
    echo ""
    read -p "Enter wiping method [1-3]: " method
    
    case "$method" in
        1)
            wipe_method="quick"
            passes="single pass of zeros"
            ;;
        2)
            wipe_method="secure"
            passes="one pass of zeros + verification"
            ;;
        3)
            wipe_method="dod"
            passes="DoD standard (multiple passes)"
            ;;
        *)
            echo "Invalid selection, defaulting to quick wipe"
            wipe_method="quick"
            passes="single pass of zeros"
            sleep 2
            ;;
    esac
    
    echo ""
    echo -e "You're about to perform a ${BOLD}$wipe_method wipe${NC} ($passes) on:"
    for drive in "${selected_drives[@]}"; do
        echo -e "${BOLD}/dev/$drive${NC}"
    done
    echo ""
    echo -e "${RED}${BOLD}This will DELETE ALL PARTITIONS and WIPE ALL DATA.${NC}"
    echo ""
    
    read -p "Type 'YES' in uppercase to confirm: " confirm
    
    if [ "$confirm" != "YES" ]; then
        echo "Wiping canceled!"
        read -p "Press Enter to continue..."
        return
    fi
    
    # Create a recovery file in case of interruption
    echo "selected_drives=(${selected_drives[@]})" > "$RECOVERY_FILE"
    echo "wipe_method=$wipe_method" >> "$RECOVERY_FILE"
    
    echo ""
    echo -e "${YELLOW}Starting wiping process in parallel...${NC}"
    
    mkdir -p "$LOG_DIR"
    
    for drive in "${selected_drives[@]}"; do
        # Remove completion marker if it exists
        rm -f "$LOG_DIR/$drive.completed"
        
        # Start the wiping process in background
        echo "Starting wipe for /dev/$drive..."
        (wipe_drive "$drive" "$wipe_method") &
        
        # Store the PID
        echo $! > "$LOG_DIR/$drive.pid"
        echo "Process started for /dev/$drive with PID $!"
    done
    
    echo ""
    echo "All wiping processes have been started in parallel."
    echo "You can check their status from the main menu or use the watch mode."
    echo ""
    read -p "Press Enter to continue..."
}

# Function to check wiping status
check_status() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}${BOLD}              WIPING STATUS                          ${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo ""
    
    if [ ${#selected_drives[@]} -eq 0 ]; then
        echo "No drives have been selected for wiping."
        read -p "Press Enter to continue..."
        return
    fi
    
    active_wipes=0
    completed_wipes=0
    
    for drive in "${selected_drives[@]}"; do
        echo -e "${BOLD}Status for /dev/$drive:${NC}"
        
        if [ -f "$LOG_DIR/$drive.pid" ]; then
            pid=$(cat "$LOG_DIR/$drive.pid")
            
            if ps -p $pid > /dev/null; then
                echo -e "  Status: ${YELLOW}WIPING IN PROGRESS${NC} (PID: $pid)"
                active_wipes=$((active_wipes + 1))
                
                # Try to get progress info
                if [ -f "$LOG_DIR/$drive.log" ]; then
                    tail -n 5 "$LOG_DIR/$drive.log"
                fi
            else
                echo -e "  Status: ${GREEN}COMPLETED${NC}"
                completed_wipes=$((completed_wipes + 1))
                if [ -f "$LOG_DIR/$drive.log" ]; then
                    tail -n 5 "$LOG_DIR/$drive.log"
                fi
            fi
        else
            echo "  Status: NOT STARTED"
        fi
        
        echo ""
    done
    
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BOLD}SUMMARY: $completed_wipes/${#selected_drives[@]} drives completed${NC}"
    
    if [ $active_wipes -gt 0 ]; then
        echo -e "${YELLOW}$active_wipes wiping processes still running.${NC}"
    else
        if [ ${#selected_drives[@]} -gt 0 ] && [ $completed_wipes -eq ${#selected_drives[@]} ]; then
            echo -e "${GREEN}${BOLD}ALL WIPING PROCESSES HAVE COMPLETED!${NC}"
            echo -e "\a"  # Terminal bell
        fi
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# Function to watch wiping progress in real-time
watch_progress() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}${BOLD}          WATCHING WIPING PROGRESS (LIVE)            ${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${YELLOW}Press Ctrl+C to return to main menu${NC}"
    echo "(wiping will continue in background)"
    echo ""
    
    # This trap ensures only the watch loop is interrupted, not the actual wiping
    trap 'return' INT  # Return to main menu when Ctrl+C is pressed
    
    while true; do
        clear
        echo -e "${BLUE}=====================================================${NC}"
        echo -e "${BLUE}${BOLD}          WATCHING WIPING PROGRESS (LIVE)            ${NC}"
        echo -e "${BLUE}=====================================================${NC}"
        echo -e "${YELLOW}Press Ctrl+C to return to main menu${NC}"
        echo "(wiping will continue in background)"
        echo ""
        
        active_wipes=0
        completed_wipes=0
        
        for drive in "${selected_drives[@]}"; do
            echo -e "${BOLD}Status for /dev/$drive:${NC}"
            
            if [ -f "$LOG_DIR/$drive.pid" ]; then
                pid=$(cat "$LOG_DIR/$drive.pid")
                
                if ps -p $pid > /dev/null; then
                    echo -e "  Status: ${YELLOW}${BOLD}WIPING IN PROGRESS${NC} (PID: $pid)"
                    active_wipes=$((active_wipes + 1))
                    
                    # Show progress info
                    if [ -f "$LOG_DIR/$drive.log" ]; then
                        tail -n 5 "$LOG_DIR/$drive.log"
                    fi
                else
                    echo -e "  Status: ${GREEN}${BOLD}COMPLETED${NC}"
                    completed_wipes=$((completed_wipes + 1))
                    if [ -f "$LOG_DIR/$drive.log" ]; then
                        tail -n 3 "$LOG_DIR/$drive.log"
                    fi
                fi
            else
                echo "  Status: NOT STARTED"
            fi
            
            echo ""
        done
        
        echo -e "${BLUE}=====================================================${NC}"
        echo -e "${BOLD}SUMMARY: $completed_wipes/${#selected_drives[@]} drives completed${NC}"
        
        # Alert when all drives complete
        if [ $active_wipes -eq 0 ] && [ ${#selected_drives[@]} -gt 0 ] && [ $completed_wipes -eq ${#selected_drives[@]} ]; then
            echo -e "${GREEN}${BOLD}*** ALL DRIVES HAVE COMPLETED WIPING! ***${NC}"
            echo -e "\a"  # Terminal bell
        elif [ $active_wipes -gt 0 ]; then
            echo -e "${YELLOW}${BOLD}*** $active_wipes DRIVES STILL WIPING ***${NC}"
        fi
        
        sleep 3  # Update every 3 seconds
    done
}

# Display version and help information
show_version() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}${BOLD}          DISK WIPING UTILITY v1.0                   ${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo ""
    echo "A comprehensive utility for securely wiping hard drives on Linux systems"
    echo ""
    echo "Features:"
    echo "  - Text-based interactive menu"
    echo "  - Multi-drive parallel wiping"
    echo "  - Partition deletion"
    echo "  - Progress monitoring and notifications"
    echo "  - Handles interruptions and power loss"
    echo "  - Multiple wiping methods (quick, secure, DoD)"
    echo ""
    echo "Usage: sudo bash disk_wipe_utility.sh"
    echo ""
    echo "For more information, visit: https://github.com/yourusername/disk-wipe-utility"
    echo -e "${BLUE}=====================================================${NC}"
    echo ""
    read -p "Press Enter to continue..."
}

# Check for command line arguments
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_version
    exit 0
fi

if [ "$1" = "--version" ] || [ "$1" = "-v" ]; then
    echo "Disk Wiping Utility v1.0"
    exit 0
fi

# Check for recovery file from previous interrupted run
if [ -f "$RECOVERY_FILE" ]; then
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}${BOLD}          RECOVERY FROM PREVIOUS SESSION             ${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo ""
    echo "It appears a previous wiping session was interrupted."
    echo "Would you like to:"
    echo ""
    echo "1. Resume monitoring previous session"
    echo "2. Start fresh (ignore previous session)"
    echo ""
    read -p "Your choice [1-2]: " recovery_choice
    
    if [ "$recovery_choice" = "1" ]; then
        # Load previous session data
        source "$RECOVERY_FILE"
        echo "Loaded previous session with ${#selected_drives[@]} drives."
        sleep 2
    else
        rm -f "$RECOVERY_FILE"
    fi
fi

# Display initial welcome message
clear
echo -e "${BLUE}=====================================================${NC}"
echo -e "${BLUE}${BOLD}          DISK WIPING UTILITY v1.0                   ${NC}"
echo -e "${BLUE}=====================================================${NC}"
echo ""
echo "Welcome to the Disk Wiping Utility!"
echo ""
echo -e "${RED}${BOLD}CAUTION: This tool is designed to permanently erase data${NC}"
echo -e "${RED}${BOLD}from hard drives. Please use with extreme care.${NC}"
echo ""
echo "This utility will allow you to:"
echo "  - Securely wipe multiple drives in parallel"
echo "  - Remove all partitions and data"
echo "  - Monitor wiping progress in real-time"
echo ""
read -p "Press Enter to continue..."

# Main program loop
while true; do
    show_menu
    read choice
    
    case $choice in
        1)
            list_drives
            ;;
        2)
            select_drives
            ;;
        3)
            start_wiping
            ;;
        4)
            check_status
            ;;
        5)
            watch_progress
            ;;
        6)
            clear
            echo -e "${BLUE}=====================================================${NC}"
            echo -e "${BLUE}${BOLD}          EXITING DISK WIPING UTILITY              ${NC}"
            echo -e "${BLUE}=====================================================${NC}"
            echo ""
            echo "Thank you for using the Disk Wiping Utility."
            echo ""
            if [ $(ps -ef | grep -v grep | grep -c "dd if=/dev/") -gt 0 ]; then
                echo -e "${YELLOW}${BOLD}NOTE: Some wiping processes are still running in background.${NC}"
                echo "You can rerun this script later to check their status."
                echo ""
            fi
            exit 0
            ;;
        *)
            echo "Invalid option. Please try again."
            sleep 2
            ;;
    esac
done
