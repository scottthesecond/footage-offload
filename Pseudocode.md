# Operations
- Offload
- Verify

# Offload
## Initiation
- Ask for project shortname (eg: S&D) and project folder path (where to offload to)
- Get list of all SD cards connected to system
- For each SD card...
    - ask user if we're offloading them as:
         - Video
         - Audio 
         - Photos
         - Maintain Folder Structure
         - Skip
    - Ask user for card name
        - they can enter 'o' (or a command key?) to open the card and look to see what it is before providing a name

## Offload
- For each SD card...
    - Create .offload file at root that stores our progress as well as info about what path the files were offloaded to
    - Create a folder in the destination folder for this SD card.  Name them as follows:
            {`v` for Video, `A` for Audio, `P` for photo, or omit if otherwise}{foldercounter}.{Project Shortname}.{Card Name if provided}
        (Where {foldercounter} is an incrementing value for all folders offloaded EVER.  Current folder number needs to be stored somewhere on the system.)
    - If type is NOT "maintain folder structure", Offload each file from the card, ignoring folders, reanaming them as you go:
            {folder name}.{filecounter}{(if Audio, add the original filename in parenthesis)}
        (Where {filecounter} is an incrementing value for the files as they are offloaded starting at 0 for each card.)
        - skip AVCHD files less than 2MB; 
        - If type is Audio, skip these file types: .SYS; .ZST 
        - If type is Video, skip these file types: .thumbs; .xml; .CTG; .DAT; .CPC; .CPG; .B00; .D00; .SCR; .THM; .log; .jpg
    - If type IS maintain fs, offload each file from the card without renaming and maintining the folder structure of the card.
    - As files are offloaded, track the original path and new path in the .offload file.  If an offload is interrupted, we should be able to use this to pick up where we left off. 
    - Once all files are offloaded, verify them.

## Verify
- Get a list of all SD cards connected to the system
- For each SD card...
    - Check for a .offload file.  If one is not provided, ask user to provide the path to the folder the card should have been offloaded to. 
    - Generate a Media Hash List for all files on the card, and in the destination
    - Compare hashes based on the path mapping in the .offload file.  If there are no path mappings, look for the hash list for both cards and ensure that there are no missing ones.
    - If we've verified that all files have been offloaded correctly, set a flag in the .offload file and ask user if they want to format the card.