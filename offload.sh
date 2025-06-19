#!/bin/bash

# Exit on error
set -e
set -u

# Parse command line arguments
DEBUG=0
COMMAND=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -debug|--debug)
            DEBUG=1
            shift
            ;;
        offload|verify)
            COMMAND="$1"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [-debug] {offload|verify}"
            echo "  -debug: Enable debug output"
            echo "  offload: Offload files from SD cards"
            echo "  verify:  Verify previously offloaded files"
            exit 1
            ;;
    esac
done

# Error handling
trap 'echo "Error occurred. Cleaning up..."' ERR

# Debug function
debug_echo() {
    if [ "$DEBUG" -eq 1 ]; then
        echo "[DEBUG] $1"
    fi
}

# Configuration
OFFLOAD_COUNTER_FILE="$HOME/.offload_counter"
OFFLOAD_COUNTER=0

# Function to get next folder number
get_next_folder_number() {
    if [ -f "$OFFLOAD_COUNTER_FILE" ]; then
        OFFLOAD_COUNTER=$(cat "$OFFLOAD_COUNTER_FILE")
    fi
    echo $((OFFLOAD_COUNTER + 1)) > "$OFFLOAD_COUNTER_FILE"
    echo $OFFLOAD_COUNTER
}

# Function to get mounted SD cards
get_mounted_cards() {
    mount | awk '
        $1 ~ /^\/dev\// && $3 ~ /^\/Volumes\// {
            fs = $4
            gsub(/^[ (]+|[,)]*$/, "", fs)
            if (fs ~ /^(exfat|fat32|msdos|vfat|ntfs|hfs|hfsplus|apfs)$/)
                print $3
        }
    '
}

# Function to create destination folder
create_destination_folder() {
    local project_shortname="$1"
    local card_name="$2"
    local card_type="$3"
    local folder_number=$(get_next_folder_number)
    
    debug_echo "Creating folder with: project=$project_shortname, card=$card_name, type=$card_type, number=$folder_number"
    
    local type_prefix=""
    case "$card_type" in
        "Video") type_prefix="v" ;;
        "Audio") type_prefix="A" ;;
        "Photo") type_prefix="P" ;;
    esac
    
    debug_echo "Type prefix: '$type_prefix'"
    
    local folder_name="${type_prefix}${folder_number}.${project_shortname}.${card_name}"
    debug_echo "Generated folder name: '$folder_name'"
    echo "$folder_name"
}

# Function to get card type from user
get_card_type() {
    echo "Select card type:" >&2
    PS3="Enter choice (1-5): "
    options=("Video" "Audio" "Photo" "Maintain Folder Structure" "Skip")
    select opt in "${options[@]}"; do
        case $opt in
            "Video") echo "Video"; break ;;
            "Audio") echo "Audio"; break ;;
            "Photo") echo "Photo"; break ;;
            "Maintain Folder Structure") echo "Maintain"; break ;;
            "Skip") echo "Skip"; break ;;
            *) echo "Invalid option $REPLY. Please select 1-5." ;;
        esac
    done
}

# Function to process a card
process_card() {
    local card="$1"
    local project_name="$2"
    local dest_path="$3"
    local card_type="$4"
    local card_name="$5"
    
    echo "Processing card: $card"
    echo "Project: $project_name"
    echo "Destination path: $dest_path"
    echo "Card type: $card_type"
    echo "Card name: $card_name"
    
    debug_echo "process_card called with: card=$card, project=$project_name, dest_path=$dest_path, type=$card_type, name=$card_name"
    
    # Create destination folder
    local dest_folder=$(create_destination_folder "$project_name" "$card_name" "$card_type")
    debug_echo "create_destination_folder returned: '$dest_folder'"
    
    local full_dest_path="$dest_path/$dest_folder"
    debug_echo "Full destination path: '$full_dest_path'"
    
    echo "Creating destination folder: $full_dest_path"
    mkdir -p "$full_dest_path"
    
    if [ -d "$full_dest_path" ]; then
        echo "Destination folder created successfully: $full_dest_path"
        debug_echo "Directory exists and is writable: $(test -w "$full_dest_path" && echo "yes" || echo "no")"
    else
        echo "ERROR: Failed to create destination folder!"
        debug_echo "mkdir exit code: $?"
        return 1
    fi
    
    # Offload files
    offload_files "$card" "$full_dest_path" "$card_type"
    
    # Ask about verification
    read -p "Offload complete. Would you like to verify now? (y/n): " verify_now
    if [ "$verify_now" = "y" ]; then
        if verify_files "$card" "$full_dest_path"; then
            read -p "Verification successful. Format card? (y/n): " format_card
            if [ "$format_card" = "y" ]; then
                echo "Formatting card..."
                # TODO: Implement card formatting
            fi
        else
            echo "Verification failed. Please check the files manually."
        fi
    fi
}

# Function to check for existing transfer
check_existing_transfer() {
    local source="$1"
    
    if [ -f "$source/.offload" ]; then
        echo "Found existing .offload file on card at $source"
        local stored_dest=$(grep "^DEST_PATH=" "$source/.offload" | cut -d'=' -f2)
        stored_dest=$(clean_path "$stored_dest")
        local stored_project=$(grep "^PROJECT=" "$source/.offload" | cut -d'=' -f2)
        local stored_card=$(grep "^CARD_NAME=" "$source/.offload" | cut -d'=' -f2)
        
        echo "Previous transfer details:"
        echo "  Project: $stored_project"
        echo "  Card Name: $stored_card"
        echo "  Destination: $stored_dest"
        
        read -p "Resume previous transfer? (y/n): " resume_transfer
        if [ "$resume_transfer" = "y" ]; then
            # Get the card type from the existing transfer
            local stored_type=""
            if grep -q "^TYPE=" "$source/.offload"; then
                stored_type=$(grep "^TYPE=" "$source/.offload" | cut -d'=' -f2)
            else
                stored_type=$(get_card_type)
                if [ "$stored_type" = "Invalid" ] || [ "$stored_type" = "Skip" ]; then
                    echo "Invalid type selected. Skipping card."
                    return 1
                fi
            fi
            
            # Process the card with stored information
            process_card "$source" "$stored_project" "$stored_dest" "$stored_type" "$stored_card"
            return 0
        fi
    fi
    return 1
}

# Function to offload files
offload_files() {
    local source="$1"
    local dest="$2"
    local card_type="$3"
    
    echo "Starting offload from $source to $dest (type: $card_type)"
    debug_echo "Source: $source"
    debug_echo "Destination: $dest"
    debug_echo "Card type: $card_type"
    
    # Check if source directory exists and is readable
    if [ ! -d "$source" ]; then
        echo "ERROR: Source directory does not exist: $source"
        return 1
    fi
    
    if [ ! -r "$source" ]; then
        echo "ERROR: Source directory is not readable: $source"
        return 1
    fi
    
    debug_echo "Source directory exists and is readable"
    
    # Check if destination directory exists and is writable
    if [ ! -d "$dest" ]; then
        echo "ERROR: Destination directory does not exist: $dest"
        return 1
    fi
    
    if [ ! -w "$dest" ]; then
        echo "ERROR: Destination directory is not writable: $dest"
        return 1
    fi
    
    debug_echo "Destination directory exists and is writable"
    
    # Create .offload file
    echo "VERSION=1.0" > "$source/.offload"
    echo "PROJECT=$PROJECT_NAME" >> "$source/.offload"
    echo "CARD_NAME=$CARD_NAME" >> "$source/.offload"
    echo "DEST_PATH=$dest" >> "$source/.offload"
    echo "TYPE=$card_type" >> "$source/.offload"
    echo "TRANSFER_START=$(date +%s)" >> "$source/.offload"
    
    case "$card_type" in
        "Video")
            echo "Processing Video files..."
            echo "Searching for files in $source..."
            
            # First, let's see what's in the source directory
            echo "Contents of source directory:"
            ls -la "$source"
            
            # Create a temporary file list to avoid subshell issues
            local temp_file_list="/tmp/offload_files_$$.txt"
            debug_echo "Creating temporary file list: $temp_file_list"
            
            # Skip AVCHD files less than 2MB and system files
            echo "Running find command..."
            find "$source" -type f -not \( -name "*.thumbs" -o -name "*.xml" -o -name "*.XML" -o -name "*.CTG" -o -name "*.DAT" -o -name "*.CPC" -o -name "*.CPG" -o -name "*.B00" -o -name "*.D00" -o -name "*.SCR" -o -name "*.THM" -o -name "*.log" -o -name "*.jpg" \) > "$temp_file_list"
            
            debug_echo "Find command completed with exit code: $?"
            debug_echo "Found $(wc -l < "$temp_file_list") files to process"
            
            # Show the first few files found for debugging
            if [ -s "$temp_file_list" ]; then
                echo "First 5 files found:"
                head -5 "$temp_file_list"
            else
                echo "WARNING: No files found by find command!"
                echo "Trying simpler find command..."
                find "$source" -type f > "$temp_file_list"
                debug_echo "Simple find found $(wc -l < "$temp_file_list") files"
                if [ -s "$temp_file_list" ]; then
                    echo "First 5 files found (simple find):"
                    head -5 "$temp_file_list"
                fi
            fi
            
            local copied_count=0
            while IFS= read -r file; do
                debug_echo "Processing file: $file"
                echo "Found file: $file"
                
                # Skip AVCHD files less than 2MB
                if [[ "$file" == *"AVCHD"* ]]; then
                    local file_size=$(stat -f%z "$file" 2>/dev/null || echo "0")
                    debug_echo "AVCHD file size: $file_size bytes"
                    if [ "$file_size" -lt 2097152 ]; then
                        echo "Skipping small AVCHD file: $file"
                        continue
                    fi
                fi
                
                echo "Copying: $file"
                debug_echo "rsync command: rsync --progress \"$file\" \"$dest/\""
                if rsync --progress "$file" "$dest/"; then
                    echo "Successfully copied: $file"
                    echo "$file=$(md5 -q "$file")" >> "$source/.offload"
                    copied_count=$((copied_count + 1))
                else
                    echo "ERROR: Failed to copy: $file"
                    debug_echo "rsync exit code: $?"
                fi
            done < "$temp_file_list"
            
            echo "Find command completed. Copied $copied_count files."
            rm -f "$temp_file_list"
            ;;
        "Audio")
            echo "Processing Audio files..."
            # Create a temporary file list to avoid subshell issues
            local temp_file_list="/tmp/offload_files_$$.txt"
            find "$source" -type f -not \( -name "*.SYS" -o -name "*.ZST" \) > "$temp_file_list"
            
            local copied_count=0
            while IFS= read -r file; do
                echo "Copying: $file"
                if rsync --progress "$file" "$dest/"; then
                    echo "Successfully copied: $file"
                    echo "$file=$(md5 -q "$file")" >> "$source/.offload"
                    copied_count=$((copied_count + 1))
                else
                    echo "ERROR: Failed to copy: $file"
                fi
            done < "$temp_file_list"
            
            echo "Audio processing completed. Copied $copied_count files."
            rm -f "$temp_file_list"
            ;;
        "Photo")
            echo "Processing Photo files..."
            # Create a temporary file list to avoid subshell issues
            local temp_file_list="/tmp/offload_files_$$.txt"
            find "$source" -type f > "$temp_file_list"
            
            local copied_count=0
            while IFS= read -r file; do
                echo "Copying: $file"
                if rsync --progress "$file" "$dest/"; then
                    echo "Successfully copied: $file"
                    echo "$file=$(md5 -q "$file")" >> "$source/.offload"
                    copied_count=$((copied_count + 1))
                else
                    echo "ERROR: Failed to copy: $file"
                fi
            done < "$temp_file_list"
            
            echo "Photo processing completed. Copied $copied_count files."
            rm -f "$temp_file_list"
            ;;
        "Maintain")
            echo "Processing with Maintain Folder Structure..."
            # Maintain folder structure but still skip system files
            if rsync --progress -r --exclude="*.thumbs" --exclude="*.xml" --exclude="*.XML" --exclude="*.CTG" --exclude="*.DAT" --exclude="*.CPC" --exclude="*.CPG" --exclude="*.B00" --exclude="*.D00" --exclude="*.SCR" --exclude="*.THM" --exclude="*.log" --exclude="*.jpg" --exclude="*.SYS" --exclude="*.ZST" "$source/" "$dest/"; then
                echo "Successfully copied files with folder structure"
            else
                echo "ERROR: Failed to copy files with folder structure"
            fi
            
            # Create hash list for verification
            find "$source" -type f -not \( -name "*.thumbs" -o -name "*.xml" -o -name "*.XML" -o -name "*.CTG" -o -name "*.DAT" -o -name "*.CPC" -o -name "*.CPG" -o -name "*.B00" -o -name "*.D00" -o -name "*.SCR" -o -name "*.THM" -o -name "*.log" -o -name "*.jpg" -o -name "*.SYS" -o -name "*.ZST" \) -print0 | while IFS= read -r -d '' file; do
                echo "$file=$(md5 -q "$file")" >> "$source/.offload"
            done
            ;;
    esac
    
    echo "TRANSFER_END=$(date +%s)" >> "$source/.offload"
    echo "Offload completed."
}

# Function to verify files
verify_files() {
    local source="$1"
    local dest="$2"
    
    if [ ! -f "$source/.offload" ]; then
        echo "No .offload file found. Cannot verify."
        return 1
    fi
    
    echo "Verifying files..."
    while IFS='=' read -r source_file hash; do
        if [[ "$source_file" == /* ]]; then
            local dest_file="$dest/$(basename "$source_file")"
            if [ -f "$dest_file" ]; then
                local current_hash=$(md5 -q "$dest_file")
                if [ "$current_hash" != "$hash" ]; then
                    echo "Hash mismatch for $source_file"
                    return 1
                fi
            else
                echo "File not found: $source_file"
                return 1
            fi
        fi
    done < <(grep -v "^#" "$source/.offload" | grep -v "^$" | grep -v "^VERSION=" | grep -v "^PROJECT=" | grep -v "^CARD_NAME=" | grep -v "^DEST_PATH=" | grep -v "^TRANSFER_" | grep -v "^STATUS=" | grep -v "^TYPE=")
    
    echo "Verification complete. All files match."
    return 0
}

# Function to clean path (remove surrounding quotes)
clean_path() {
    local path="$1"
    # Remove surrounding single or double quotes
    path="${path%\"}"
    path="${path%\'}"
    path="${path#\"}"
    path="${path#\'}"
    echo "$path"
}

# Main offload function
do_offload() {
    echo "SD Card Offload Tool"
    echo "-------------------"

    # Get project information
    read -p "Enter project shortname: " PROJECT_NAME
    read -p "Enter destination folder path: " DEST_PATH
    DEST_PATH=$(clean_path "$DEST_PATH")
    echo "Cleaned destination path: $DEST_PATH"

    # Get list of mounted cards
    CARDS=($(get_mounted_cards))

    if [ ${#CARDS[@]} -eq 0 ]; then
        echo "No SD cards found. Please insert a card and try again."
        exit 1
    fi

    # Process each card
    for card in "${CARDS[@]}"; do
        echo "Found card at: $card"
        
        # Check for existing transfer first
        if ! check_existing_transfer "$card"; then
            # If not resuming, proceed with normal flow
            read -p "Process this card? (y/n): " process_card
            
            if [ "$process_card" = "y" ]; then
                local type=$(get_card_type)
                if [ "$type" = "Invalid" ] || [ "$type" = "Skip" ]; then
                    echo "Invalid type selected. Skipping card."
                    continue
                fi
                
                read -p "Enter card name (or 'o' to open card): " CARD_NAME
                
                if [ "$CARD_NAME" = "o" ]; then
                    open "$card"
                    read -p "Enter card name: " CARD_NAME
                fi
                
                process_card "$card" "$PROJECT_NAME" "$DEST_PATH" "$type" "$CARD_NAME"
            fi
        fi
    done

    echo "Offload process complete."
}

# Main verify function
do_verify() {
    echo "SD Card Verification Tool"
    echo "------------------------"

    # Get list of mounted cards
    CARDS=($(get_mounted_cards))

    if [ ${#CARDS[@]} -eq 0 ]; then
        echo "No SD cards found. Please insert a card and try again."
        exit 1
    fi

    # Process each card
    for card in "${CARDS[@]}"; do
        echo "Found card at: $card"
        read -p "Verify this card? (y/n): " verify_card
        
        if [ "$verify_card" = "y" ]; then
            if [ ! -f "$card/.offload" ]; then
                read -p "No .offload file found. Enter destination folder path: " DEST_PATH
                DEST_PATH=$(clean_path "$DEST_PATH")
            else
                DEST_PATH=$(grep "^DEST_PATH=" "$card/.offload" | cut -d'=' -f2)
                DEST_PATH=$(clean_path "$DEST_PATH")
            fi
            
            if verify_files "$card" "$DEST_PATH"; then
                read -p "Verification successful. Format card? (y/n): " format_card
                if [ "$format_card" = "y" ]; then
                    echo "Formatting card..."
                    # TODO: Implement card formatting
                fi
            else
                echo "Verification failed. Please check the files manually."
            fi
        fi
    done

    echo "Verification process complete."
}

# Main script
case "$COMMAND" in
    "offload")
        do_offload
        ;;
    "verify")
        do_verify
        ;;
    *)
        echo "Usage: $0 [-debug] {offload|verify}"
        echo "  -debug: Enable debug output"
        echo "  offload: Offload files from SD cards"
        echo "  verify:  Verify previously offloaded files"
        exit 1
        ;;
esac 