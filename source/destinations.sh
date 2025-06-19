#!/bin/bash

# Configuration
RECENT_DEST_FILE="$HOME/.unf_offload_recent"
VOLUMES=(
    "/Volumes/Production:Production"
    "/Volumes/Events:Events"
)

# Function to save the most recent destination
save_recent_destination() {
    local destination="$1"
    echo "$destination" > "$RECENT_DEST_FILE"
}

# Function to get the most recent destination
get_recent_destination() {
    if [ -f "$RECENT_DEST_FILE" ]; then
        cat "$RECENT_DEST_FILE"
    else
        return 1
    fi
}

# Function to recursively select folders with "Offload Here" option
select_folder_recursive() {
    local current_path="$1"
    local volume_name="$2"
    
    while true; do
        # Get list of subdirectories using a temporary array
        local subdirs=()
        while IFS= read -r item; do
            if [ -d "$current_path/$item" ]; then
                subdirs+=("$item")
            fi
        done < <(ls -1 "$current_path" | grep -v "^\.$" | grep -v "^\.\.$" | grep -v "^#recycle$")
        
        # Build options array
        local options=()
        if [ ${#subdirs[@]} -gt 0 ]; then
            options+=("${subdirs[@]}")
        fi
        options+=("Offload Here")
        
        # Show current path and options
        echo "Current location: $current_path" >&2
        echo "Select an option:" >&2
        PS3="Enter your choice: "
        
        select choice in "${options[@]}"; do
            if [ -n "$choice" ]; then
                if [ "$choice" = "Offload Here" ]; then
                    echo "$current_path"
                    return 0
                else
                    # Navigate to subfolder
                    current_path="$current_path/$choice"
                    break
                fi
            else
                echo "Invalid choice. Please select a valid number." >&2
            fi
        done
    done
}

# Function to handle volume selection
handle_volume_selection() {
    local volume_path="$1"
    local volume_name="$2"
    
    if [ ! -d "$volume_path" ]; then
        echo "Please mount the $volume_name share or choose a different option." >&2
        return 1
    fi
    
    local result
    result=$(select_folder_recursive "$volume_path" "$volume_name")
    if [ $? -eq 0 ]; then
        save_recent_destination "$result"
        echo "$result"
        return 0
    else
        return 1
    fi
}

# Function to handle custom path input
handle_custom_path() {
    read -p "Enter destination path: " destination
    save_recent_destination "$destination"
    echo "$destination"
}

# Function to get destination from user
get_destination() {
    echo "Destination not provided. Please choose an option:"
    
    # Check if we have a recent destination
    local recent_dest=""
    if get_recent_destination > /dev/null 2>&1; then
        recent_dest=$(get_recent_destination)
        if [ -d "$recent_dest" ]; then
            echo "Recent destination: $recent_dest"
        else
            recent_dest=""
        fi
    fi
    
    # Build menu options
    local menu_options=("Enter a custom path")
    
    # Add volume options
    for volume_info in "${VOLUMES[@]}"; do
        IFS=':' read -r volume_path volume_name <<< "$volume_info"
        menu_options+=("Select from $volume_name")
    done
    
    # Add recent destination if available
    if [ -n "$recent_dest" ]; then
        menu_options+=("$recent_dest")
    fi
    
    PS3="Enter your choice: "
    select choice in "${menu_options[@]}"; do
        case $choice in
            "Enter a custom path")
                handle_custom_path
                break
                ;;
            "Select from Production")
                handle_volume_selection "/Volumes/Production" "Production"
                break
                ;;
            "Select from Events")
                handle_volume_selection "/Volumes/Events" "Events"
                break
                ;;
            "$recent_dest")
                echo "$recent_dest"
                break
                ;;
            *)
                local max_choice=${#menu_options[@]}
                echo "Invalid choice. Please select 1-$max_choice." >&2
                ;;
        esac
    done
}
