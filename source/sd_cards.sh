#!/bin/bash

# Function to get a list of SD cards connected to the system
# Outputs a newline-separated list of SD card mount points
get_sd_cards() {
    local sd_cards=()
    
    # Check if /Volumes directory exists
    if [ ! -d "/Volumes" ]; then
        return 1
    fi
    
    # Get all mounted volumes
    while IFS= read -r volume; do
        # Skip if empty or system volumes
        if [ -z "$volume" ] || [ "$volume" = "Macintosh HD" ]; then
            continue
        fi
        
        local volume_path="/Volumes/$volume"
        
        # Check if it's a directory (not a symlink to network share)
        if [ ! -d "$volume_path" ]; then
            continue
        fi
        
        # Check if it's not a network share
        if is_network_share "$volume_path"; then
            continue
        fi
        
        # Additional checks for SD card characteristics
        if is_likely_sd_card "$volume_path"; then
            sd_cards+=("$volume_path")
        fi
        
    done < <(ls -1 "/Volumes" 2>/dev/null)
    
    # Output the results
    if [ ${#sd_cards[@]} -eq 0 ]; then
        return 1
    fi
    
    printf '%s\n' "${sd_cards[@]}"
    return 0
}

# Function to check if a volume is likely a network share
is_network_share() {
    local volume_path="$1"
    
    # Check if it's a symlink (common for network shares)
    if [ -L "$volume_path" ]; then
        return 0
    fi
    
    # Check mount info for network filesystem types
    local mount_info
    mount_info=$(mount | grep "$volume_path" 2>/dev/null)
    if echo "$mount_info" | grep -q -E "(smbfs|nfs|afp|webdav)"; then
        return 0  # True - it's a network share
    fi
    
    # Check if the volume name contains common network share indicators
    local volume_name
    volume_name=$(basename "$volume_path")
    if echo "$volume_name" | grep -q -E "(share|server|nas|network|smb|nfs)"; then
        return 0  # True - it's likely a network share
    fi
    
    return 1  # False - not a network share
}

# Function to check if a volume is likely an SD card
is_likely_sd_card() {
    local volume_path="$1"
    
    # Check if the volume has typical SD card characteristics
    if ! is_removable_device "$volume_path"; then
        return 1
    fi
    
    # Check volume name for common SD card patterns
    local volume_name
    volume_name=$(basename "$volume_path")
    if echo "$volume_name" | grep -q -E "(SD|CARD|NO NAME|UNTITLED|DCIM|PHOTOS|VIDEOS)"; then
        return 0
    fi
    
    # Check if the volume has typical camera/media folder structure
    if has_camera_structure "$volume_path"; then
        return 0
    fi
    
    # Check filesystem type (SD cards are usually FAT32 or exFAT)
    if has_sd_card_filesystem "$volume_path"; then
        return 0
    fi
    
    return 1
}

# Function to check if a device is removable
is_removable_device() {
    local volume_path="$1"
    
    # Use diskutil to get device information
    local device_info
    device_info=$(diskutil info "$volume_path" 2>/dev/null)
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    # Check if it's removable (various possible outputs)
    if echo "$device_info" | grep -qE "Removable Media:[[:space:]]*(Yes|Removable)"; then
        return 0
    fi
    
    # Check if it's an external device
    if echo "$device_info" | grep -q "Device / Media Name:.*SD"; then
        return 0
    fi
    
    # Check if protocol is Secure Digital
    if echo "$device_info" | grep -q "Protocol:[[:space:]]*Secure Digital"; then
        return 0
    fi
    return 1
}

# Function to check if volume has typical camera folder structure
has_camera_structure() {
    local volume_path="$1"
    
    # Check for common camera/media folders
    local camera_folders=("DCIM" "MISC" "PRIVATE" "AVCHD" "MP_ROOT" "VIDEO" "PHOTO")
    for folder in "${camera_folders[@]}"; do
        if [ -d "$volume_path/$folder" ]; then
            return 0
        fi
    done
    return 1
}

# Function to check if volume has SD card filesystem
has_sd_card_filesystem() {
    local volume_path="$1"
    
    # Get filesystem information
    local fs_info
    fs_info=$(diskutil info "$volume_path" 2>/dev/null | grep "File System Personality:" | awk '{print $4}')
    
    # Common SD card filesystems
    case "$fs_info" in
        "MS-DOS FAT32"|"ExFAT"|"FAT32"|"FAT16")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
} 