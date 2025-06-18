#!/bin/bash

# Exit on error
set -e
set -u

# Error handling
trap 'echo "Error occurred. Cleaning up..."' ERR

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
    mount | grep -i "sd" | awk '{print $3}'
}

# Function to create destination folder
create_destination_folder() {
    local project_shortname="$1"
    local card_name="$2"
    local card_type="$3"
    local folder_number=$(get_next_folder_number)
    
    local type_prefix=""
    case "$card_type" in
        "Video") type_prefix="v" ;;
        "Audio") type_prefix="A" ;;
        "Photo") type_prefix="P" ;;
    esac
    
    local folder_name="${type_prefix}${folder_number}.${project_shortname}.${card_name}"
    echo "$folder_name"
}

# Function to get card type from user
get_card_type() {
    echo "Select card type:"
    echo "1) Video"
    echo "2) Audio"
    echo "3) Photo"
    echo "4) Maintain Folder Structure"
    echo "5) Skip"
    read -p "Enter choice (1-5): " card_type
    
    case "$card_type" in
        1) echo "Video" ;;
        2) echo "Audio" ;;
        3) echo "Photo" ;;
        4) echo "Maintain" ;;
        5) echo "Skip" ;;
        *) echo "Invalid" ;;
    esac
}

# Function to process a card
process_card() {
    local card="$1"
    local project_name="$2"
    local dest_path="$3"
    local card_type="$4"
    local card_name="$5"
    
    # Create destination folder
    local dest_folder=$(create_destination_folder "$project_name" "$card_name" "$card_type")
    mkdir -p "$dest_path/$dest_folder"
    
    # Offload files
    offload_files "$card" "$dest_path/$dest_folder" "$card_type"
    
    # Ask about verification
    read -p "Offload complete. Would you like to verify now? (y/n): " verify_now
    if [ "$verify_now" = "y" ]; then
        if verify_files "$card" "$dest_path/$dest_folder"; then
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
    
    # Create .offload file
    echo "VERSION=1.0" > "$source/.offload"
    echo "PROJECT=$PROJECT_NAME" >> "$source/.offload"
    echo "CARD_NAME=$CARD_NAME" >> "$source/.offload"
    echo "DEST_PATH=$dest" >> "$source/.offload"
    echo "TYPE=$card_type" >> "$source/.offload"
    echo "TRANSFER_START=$(date +%s)" >> "$source/.offload"
    
    case "$card_type" in
        "Video")
            # Skip AVCHD files less than 2MB and system files
            find "$source" -type f -not \( -name "*.thumbs" -o -name "*.xml" -o -name "*.CTG" -o -name "*.DAT" -o -name "*.CPC" -o -name "*.CPG" -o -name "*.B00" -o -name "*.D00" -o -name "*.SCR" -o -name "*.THM" -o -name "*.log" -o -name "*.jpg" \) -print0 | while IFS= read -r -d '' file; do
                # Skip AVCHD files less than 2MB
                if [[ "$file" == *"AVCHD"* ]] && [ $(stat -f%z "$file") -lt 2097152 ]; then
                    echo "Skipping small AVCHD file: $file"
                    continue
                fi
                rsync --progress "$file" "$dest/"
                echo "$file=$(md5sum "$file" | cut -d' ' -f1)" >> "$source/.offload"
            done
            ;;
        "Audio")
            # Skip system files
            find "$source" -type f -not \( -name "*.SYS" -o -name "*.ZST" \) -print0 | while IFS= read -r -d '' file; do
                rsync --progress "$file" "$dest/"
                echo "$file=$(md5sum "$file" | cut -d' ' -f1)" >> "$source/.offload"
            done
            ;;
        "Photo")
            # No specific exclusions for photos
            find "$source" -type f -print0 | while IFS= read -r -d '' file; do
                rsync --progress "$file" "$dest/"
                echo "$file=$(md5sum "$file" | cut -d' ' -f1)" >> "$source/.offload"
            done
            ;;
        "Maintain")
            # Maintain folder structure but still skip system files
            rsync --progress -r --exclude="*.thumbs" --exclude="*.xml" --exclude="*.CTG" --exclude="*.DAT" --exclude="*.CPC" --exclude="*.CPG" --exclude="*.B00" --exclude="*.D00" --exclude="*.SCR" --exclude="*.THM" --exclude="*.log" --exclude="*.jpg" --exclude="*.SYS" --exclude="*.ZST" "$source/" "$dest/"
            find "$source" -type f -not \( -name "*.thumbs" -o -name "*.xml" -o -name "*.CTG" -o -name "*.DAT" -o -name "*.CPC" -o -name "*.CPG" -o -name "*.B00" -o -name "*.D00" -o -name "*.SCR" -o -name "*.THM" -o -name "*.log" -o -name "*.jpg" -o -name "*.SYS" -o -name "*.ZST" \) -print0 | while IFS= read -r -d '' file; do
                echo "$file=$(md5sum "$file" | cut -d' ' -f1)" >> "$source/.offload"
            done
            ;;
    esac
    
    echo "TRANSFER_END=$(date +%s)" >> "$source/.offload"
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
                local current_hash=$(md5sum "$dest_file" | cut -d' ' -f1)
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

# Main offload function
do_offload() {
    echo "SD Card Offload Tool"
    echo "-------------------"

    # Get project information
    read -p "Enter project shortname: " PROJECT_NAME
    read -p "Enter destination folder path: " DEST_PATH

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
            else
                DEST_PATH=$(grep "^DEST_PATH=" "$card/.offload" | cut -d'=' -f2)
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
case "${1:-}" in
    "offload")
        do_offload
        ;;
    "verify")
        do_verify
        ;;
    *)
        echo "Usage: $0 {offload|verify}"
        echo "  offload: Offload files from SD cards"
        echo "  verify:  Verify previously offloaded files"
        exit 1
        ;;
esac 