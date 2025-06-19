#!/bin/bash

source source/destinations.sh

# Function to handle offload operation
offload() {
    local destination="$1"
    
    if [ -z "$destination" ]; then
        destination=$(get_destination)
        if [ $? -ne 0 ]; then
            echo "Failed to get destination"
            exit 1
        fi
    fi
    
    echo "Offloading to: $destination"
    echo "unimplemented"
}

# Function to handle verify operation
verify() {
    local destination="$1"
    
    if [ -z "$destination" ]; then
        destination=$(get_destination)
        if [ $? -ne 0 ]; then
            echo "Failed to get destination"
            exit 1
        fi
    fi
    
    echo "Verifying destination: $destination"
    echo "unimplemented"
}

# Main script logic
case "$1" in
    "offload")
        offload "$2"
        ;;
    "verify")
        verify "$2"
        ;;
    *)
        echo "Usage: $0 {offload|verify} [destination]"
        echo "  offload - Run offload function"
        echo "  verify  - Run verify function"
        echo "  destination - Optional path or will prompt for selection"
        exit 1
        ;;
esac
