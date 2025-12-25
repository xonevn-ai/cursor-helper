#!/bin/bash

# Set error handling
set -e

# Define log file path
LOG_FILE="/tmp/cursor_linux_id_modifier.log"

# Initialize log file
initialize_log() {
    echo "========== Cursor ID Modification Tool Log Start $(date) ==========" > "$LOG_FILE"
    chmod 644 "$LOG_FILE"
}

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log functions - output to both terminal and log file
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
    echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

# Record command output to log file
log_cmd_output() {
    local cmd="$1"
    local msg="$2"
    echo "[CMD] $(date '+%Y-%m-%d %H:%M:%S') Executing command: $cmd" >> "$LOG_FILE"
    echo "[CMD] $msg:" >> "$LOG_FILE"
    eval "$cmd" 2>&1 | tee -a "$LOG_FILE"
    echo "" >> "$LOG_FILE"
}

# Get current user
get_current_user() {
    if [ "$EUID" -eq 0 ]; then
        echo "$SUDO_USER"
    else
        echo "$USER"
    fi
}

CURRENT_USER=$(get_current_user)
if [ -z "$CURRENT_USER" ]; then
    log_error "Unable to get username"
    exit 1
fi

# Define Cursor paths on Linux
CURSOR_CONFIG_DIR="$HOME/.config/Cursor"
STORAGE_FILE="$CURSOR_CONFIG_DIR/User/globalStorage/storage.json"
BACKUP_DIR="$CURSOR_CONFIG_DIR/User/globalStorage/backups"

# --- New: Installation-related variables ---
APPIMAGE_SEARCH_DIR="/opt/CursorInstall" # AppImage search directory, can be modified as needed
APPIMAGE_PATTERN="Cursor-*.AppImage"     # AppImage filename pattern
INSTALL_DIR="/opt/Cursor"                # Cursor final installation directory
ICON_PATH="/usr/share/icons/cursor.png"
DESKTOP_FILE="/usr/share/applications/cursor-cursor.desktop"
# --- End: Installation-related variables ---

# Possible Cursor binary paths - added standard installation path
CURSOR_BIN_PATHS=(
    "/usr/bin/cursor"
    "/usr/local/bin/cursor"
    "$INSTALL_DIR/cursor"               # Add standard installation path
    "$HOME/.local/bin/cursor"
    "/snap/bin/cursor"
)

# Find Cursor installation path
find_cursor_path() {
    log_info "Searching for Cursor installation path..."
    
    for path in "${CURSOR_BIN_PATHS[@]}"; do
        if [ -f "$path" ] && [ -x "$path" ]; then # Ensure file exists and is executable
            log_info "Found Cursor installation path: $path"
            CURSOR_PATH="$path"
            return 0
        fi
    done

    # Try to locate via which command
    if command -v cursor &> /dev/null; then
        CURSOR_PATH=$(which cursor)
        log_info "Found Cursor via which: $CURSOR_PATH"
        return 0
    fi
    
    # Try to find possible installation paths (limit search scope and type)
    local cursor_paths=$(find /usr /opt $HOME/.local -path "$INSTALL_DIR/cursor" -o -name "cursor" -type f -executable 2>/dev/null)
    if [ -n "$cursor_paths" ]; then
        # Prefer standard installation path
        local standard_path=$(echo "$cursor_paths" | grep "$INSTALL_DIR/cursor" | head -1)
        if [ -n "$standard_path" ]; then
            CURSOR_PATH="$standard_path"
        else
            CURSOR_PATH=$(echo "$cursor_paths" | head -1)
        fi
        log_info "Found Cursor via search: $CURSOR_PATH"
        return 0
    fi
    
    log_warn "Cursor executable file not found"
    return 1
}

# Find and locate Cursor resource file directory
find_cursor_resources() {
    log_info "Searching for Cursor resource directory..."
    
    # Possible resource directory paths - added standard installation directory
    local resource_paths=(
        "$INSTALL_DIR" # Add standard installation path
        "/usr/lib/cursor"
        "/usr/share/cursor"
        "$HOME/.local/share/cursor"
    )
    
    for path in "${resource_paths[@]}"; do
        if [ -d "$path/resources" ]; then # Check if resources subdirectory exists
            log_info "Found Cursor resource directory: $path"
            CURSOR_RESOURCES="$path"
            return 0
        fi
         if [ -d "$path/app" ]; then # Some versions may have app directory directly
             log_info "Found Cursor resource directory (app): $path"
             CURSOR_RESOURCES="$path"
             return 0
         fi
    done
    
    # If CURSOR_PATH exists, try to infer from it
    if [ -n "$CURSOR_PATH" ]; then
        local base_dir=$(dirname "$CURSOR_PATH")
        # Check common relative paths
        if [ -d "$base_dir/resources" ]; then
            CURSOR_RESOURCES="$base_dir"
            log_info "Found resource directory via binary path: $CURSOR_RESOURCES"
            return 0
        elif [ -d "$base_dir/../resources" ]; then # e.g., inside bin directory
            CURSOR_RESOURCES=$(realpath "$base_dir/..")
            log_info "Found resource directory via binary path: $CURSOR_RESOURCES"
            return 0
        elif [ -d "$base_dir/../lib/cursor/resources" ]; then # Another common structure
            CURSOR_RESOURCES=$(realpath "$base_dir/../lib/cursor")
            log_info "Found resource directory via binary path: $CURSOR_RESOURCES"
            return 0
        fi
    fi
    
    log_warn "Cursor resource directory not found"
    return 1
}

# Check permissions
check_permissions() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run this script with sudo (permissions required for installation and system file modification)"
        echo "Example: sudo $0"
        exit 1
    fi
}

# --- New/Refactored: Install Cursor from local AppImage ---
install_cursor_appimage() {
    log_info "Starting to install Cursor from local AppImage..."
    local found_appimage_path=""

    # Ensure search directory exists
    mkdir -p "$APPIMAGE_SEARCH_DIR"

    # Find AppImage file
    find_appimage() {
        found_appimage_path=$(find "$APPIMAGE_SEARCH_DIR" -maxdepth 1 -name "$APPIMAGE_PATTERN" -print -quit)
        if [ -z "$found_appimage_path" ]; then
            return 1
        else
            return 0
        fi
    }

    if ! find_appimage; then
        log_warn "File '$APPIMAGE_PATTERN' not found in '$APPIMAGE_SEARCH_DIR' directory."
        # --- New: Add filename format reminder ---
        log_info "Please ensure AppImage filename format is similar to: Cursor-version-architecture.AppImage (e.g.: Cursor-1.0.6-aarch64.AppImage or Cursor-x.y.z-x86_64.AppImage)"
        # --- End: Add filename format reminder ---
        # Wait for user to place file
        read -p $"Please place the Cursor AppImage file into '$APPIMAGE_SEARCH_DIR' directory, then press Enter to continue..."

        # Search again
        if ! find_appimage; then
            log_error "Still unable to find '$APPIMAGE_PATTERN' file in '$APPIMAGE_SEARCH_DIR'. Installation aborted."
            return 1
        fi
    fi

    log_info "Found AppImage file: $found_appimage_path"
    local appimage_filename=$(basename "$found_appimage_path")

    # Enter search directory to operate, avoid path issues
    local current_dir=$(pwd)
    cd "$APPIMAGE_SEARCH_DIR" || { log_error "Unable to enter directory: $APPIMAGE_SEARCH_DIR"; return 1; }

    log_info "Setting executable permissions for '$appimage_filename'..."
    chmod +x "$appimage_filename" || {
        log_error "Failed to set executable permissions: $appimage_filename"
        cd "$current_dir"
        return 1
    }

    log_info "Extracting AppImage file '$appimage_filename'..."
    # Create temporary extraction directory
    local extract_dir="squashfs-root"
    rm -rf "$extract_dir" # Clean up old extraction directory (if exists)
    
    # Execute extraction, redirect output to avoid interference
    if ./"$appimage_filename" --appimage-extract > /dev/null; then
        log_info "AppImage extracted successfully to '$extract_dir'"
    else
        log_error "Failed to extract AppImage: $appimage_filename"
        rm -rf "$extract_dir" # Clean up failed extraction
        cd "$current_dir"
        return 1
    fi

    # Check expected directory structure after extraction
    local cursor_source_dir=""
    if [ -d "$extract_dir/usr/share/cursor" ]; then
       cursor_source_dir="$extract_dir/usr/share/cursor"
    elif [ -d "$extract_dir" ]; then # Some AppImages may have files directly in root
       # Further check if key files/directories exist
       if [ -f "$extract_dir/cursor" ] && [ -d "$extract_dir/resources" ]; then
           cursor_source_dir="$extract_dir"
       fi
    fi

    if [ -z "$cursor_source_dir" ]; then
        log_error "Expected Cursor file structure not found in extracted directory '$extract_dir' (e.g. 'usr/share/cursor' or directly containing 'cursor' and 'resources')."
        rm -rf "$extract_dir"
        cd "$current_dir"
        return 1
    fi
     log_info "Found Cursor source files at: $cursor_source_dir"


    log_info "Installing Cursor to '$INSTALL_DIR'..."
    # If installation directory already exists, delete it first (ensure fresh installation)
    if [ -d "$INSTALL_DIR" ]; then
        log_warn "Found existing installation directory '$INSTALL_DIR', will remove first..."
        rm -rf "$INSTALL_DIR" || { log_error "Failed to remove old installation directory: $INSTALL_DIR"; cd "$current_dir"; return 1; }
    fi
    
    # Create parent directory of installation directory (if needed) and set permissions
    mkdir -p "$(dirname "$INSTALL_DIR")"
    
    # Move extracted contents to installation directory
    if mv "$cursor_source_dir" "$INSTALL_DIR"; then
        log_info "Successfully moved files to '$INSTALL_DIR'"
        # Ensure installation directory and contents belong to current user (if needed)
        chown -R "$CURRENT_USER":"$(id -g -n "$CURRENT_USER")" "$INSTALL_DIR" || log_warn "Failed to set '$INSTALL_DIR' file ownership, may need manual adjustment"
        chmod -R u+rwX,go+rX,go-w "$INSTALL_DIR" || log_warn "Failed to set '$INSTALL_DIR' file permissions, may need manual adjustment"
    else
        log_error "Failed to move files to installation directory '$INSTALL_DIR'"
        rm -rf "$extract_dir" # Ensure cleanup
        rm -rf "$INSTALL_DIR" # Clean up partially moved files
        cd "$current_dir"
        return 1
    fi

    # Handle icon and desktop shortcut (search from script's original directory)
    cd "$current_dir" # Return to original directory to find icon and other files

    local icon_source="./cursor.png"
    local desktop_source="./cursor-cursor.desktop"

    if [ -f "$icon_source" ]; then
        log_info "Installing icon..."
        mkdir -p "$(dirname "$ICON_PATH")"
        cp "$icon_source" "$ICON_PATH" || log_warn "Unable to copy icon file '$icon_source' to '$ICON_PATH'"
        chmod 644 "$ICON_PATH" || log_warn "Failed to set icon file permissions: $ICON_PATH"
    else
        log_warn "Icon file '$icon_source' does not exist in script's current directory, skipping icon installation."
        log_warn "Please place 'cursor.png' file in script directory '$current_dir' and re-run installation (if icon is needed)."
    fi

    if [ -f "$desktop_source" ]; then
        log_info "Installing desktop shortcut..."
         mkdir -p "$(dirname "$DESKTOP_FILE")"
        cp "$desktop_source" "$DESKTOP_FILE" || log_warn "Unable to create desktop shortcut '$desktop_source' to '$DESKTOP_FILE'"
        chmod 644 "$DESKTOP_FILE" || log_warn "Failed to set desktop file permissions: $DESKTOP_FILE"

        # Update desktop database
        log_info "Updating desktop database..."
        update-desktop-database "$(dirname "$DESKTOP_FILE")" &> /dev/null || log_warn "Unable to update desktop database, shortcut may not appear immediately"
    else
        log_warn "Desktop file '$desktop_source' does not exist in script's current directory, skipping shortcut installation."
         log_warn "Please place 'cursor-cursor.desktop' file in script directory '$current_dir' and re-run installation (if shortcut is needed)."
    fi

    # Create symbolic link to /usr/local/bin
    log_info "Creating command-line launch link..."
    ln -sf "$INSTALL_DIR/cursor" /usr/local/bin/cursor || log_warn "Unable to create command-line link '/usr/local/bin/cursor'"

    # Clean up temporary files
    log_info "Cleaning up temporary files..."
    cd "$APPIMAGE_SEARCH_DIR" # Return to search directory for cleanup
    rm -rf "$extract_dir"
    log_info "Deleting original AppImage file: $found_appimage_path"
    rm -f "$appimage_filename" # Delete AppImage file

    cd "$current_dir" # Ensure return to final directory

    log_info "Cursor installation successful! Installation directory: $INSTALL_DIR"
    return 0
}
# --- End: Installation function ---

# Check and close Cursor processes
check_and_kill_cursor() {
    log_info "Checking Cursor processes..."
    
    local attempt=1
    local max_attempts=5
    
    # Function: Get process detailed information
    get_process_details() {
        local process_name="$1"
        log_debug "Getting detailed information for $process_name process:"
        ps aux | grep -i "cursor" | grep -v grep | grep -v "cursor_linux_id_modifier.sh"
    }
    
    while [ $attempt -le $max_attempts ]; do
        # Use more precise matching to get Cursor processes, excluding current script and grep processes
        CURSOR_PIDS=$(ps aux | grep -i "cursor" | grep -v "grep" | grep -v "cursor_linux_id_modifier.sh" | awk '{print $2}' || true)
        
        if [ -z "$CURSOR_PIDS" ]; then
            log_info "No running Cursor processes found"
            return 0
        fi
        
        log_warn "Found Cursor processes running"
        get_process_details "cursor"
        
        log_warn "Attempting to close Cursor processes..."
        
        if [ $attempt -eq $max_attempts ]; then
            log_warn "Attempting to force terminate processes..."
            kill -9 $CURSOR_PIDS 2>/dev/null || true
        else
            kill $CURSOR_PIDS 2>/dev/null || true
        fi
        
        sleep 1
        
        # Check again if processes are still running, excluding current script and grep processes
        if ! ps aux | grep -i "cursor" | grep -v "grep" | grep -v "cursor_linux_id_modifier.sh" > /dev/null; then
            log_info "Cursor processes have been successfully closed"
            return 0
        fi
        
        log_warn "Waiting for processes to close, attempt $attempt/$max_attempts..."
        ((attempt++))
    done
    
    log_error "Unable to close Cursor processes after $max_attempts attempts"
    get_process_details "cursor"
    log_error "Please manually close the processes and retry"
    exit 1
}

# Backup configuration file
backup_config() {
    if [ ! -f "$STORAGE_FILE" ]; then
        log_warn "Configuration file '$STORAGE_FILE' does not exist, skipping backup"
        return 0
    fi
    
    mkdir -p "$BACKUP_DIR"
    local backup_file="$BACKUP_DIR/storage.json.backup_$(date +%Y%m%d_%H%M%S)"
    
    if cp "$STORAGE_FILE" "$backup_file"; then
        chmod 644 "$backup_file"
        # Ensure backup file belongs to correct user
        chown "$CURRENT_USER":"$(id -g -n "$CURRENT_USER")" "$backup_file" || log_warn "Failed to set backup file ownership: $backup_file"
        log_info "Configuration backed up to: $backup_file"
    else
        log_error "Backup failed: $STORAGE_FILE"
        exit 1
    fi
    return 0 # Explicitly return success
}

# Generate random ID
generate_random_id() {
    # Generate 32 bytes (64 hexadecimal characters) random number
    openssl rand -hex 32
}

# Generate random UUID
generate_uuid() {
    # Use uuidgen on Linux to generate UUID
    if command -v uuidgen &> /dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    else
        # Alternative: Use /proc/sys/kernel/random/uuid
        if [ -f /proc/sys/kernel/random/uuid ]; then
            cat /proc/sys/kernel/random/uuid
        else
            # Final alternative: Use openssl to generate
            openssl rand -hex 16 | sed 's/\\(..\\)\\(..\\)\\(..\\)\\(..\\)\\(..\\)\\(..\\)\\(..\\)\\(..\\)/\\1\\2\\3\\4-\\5\\6-\\7\\8-\\9\\10-\\11\\12\\13\\14\\15\\16/'
        fi
    fi
}

# Modify existing file
modify_or_add_config() {
    local key="$1"
    local value="$2"
    local file="$3"
    
    if [ ! -f "$file" ]; then
        log_error "Configuration file does not exist: $file"
        return 1
    fi
    
    # Ensure file is writable by current user (root)
    chmod u+w "$file" || {
        log_error "Unable to modify file permissions (write): $file"
        return 1
    }
    
    # Create temporary file
    local temp_file=$(mktemp)
    
    # Check if key exists
    if grep -q "\"$key\":[[:space:]]*\"[^\"]*\"" "$file"; then
        # Key exists, perform replacement (more precise matching)
        sed "s/\\(\"$key\"\\):[[:space:]]*\"[^\"]*\"/\\1: \"$value\"/" "$file" > "$temp_file" || {
            log_error "Failed to modify configuration (replace): $key in $file"
            rm -f "$temp_file"
            chmod u-w "$file" # Restore permissions
            return 1
        }
         log_debug "Replaced key '$key' in file '$file'"
    elif grep -q "}" "$file"; then
         # Key does not exist, add new key-value pair before last '}'
         # Note: This method is fragile, will fail if JSON format is non-standard or last line is not '}'
         sed '$ s/}/,\n    "'$key'\": "'$value'\"\n}/' "$file" > "$temp_file" || {
             log_error "Failed to add configuration (inject): $key to $file"
             rm -f "$temp_file"
             chmod u-w "$file" # Restore permissions
             return 1
         }
         log_debug "Added key '$key' to file '$file'"
    else
         log_error "Unable to determine how to add configuration: $key to $file (file structure may be non-standard)"
         rm -f "$temp_file"
         chmod u-w "$file" # Restore permissions
         return 1
    fi

    # Check if temporary file is valid
    if [ ! -s "$temp_file" ]; then
        log_error "Temporary file generated after modification or addition is empty: $key in $file"
        rm -f "$temp_file"
        chmod u-w "$file" # Restore permissions
        return 1
    fi
    
    # Use cat to replace original file content
    cat "$temp_file" > "$file" || {
        log_error "Unable to write updated configuration to file: $file"
        rm -f "$temp_file"
        # Try to restore permissions (if failed, it's okay)
        chmod u-w "$file" || true
        return 1
    }
    
    rm -f "$temp_file"
    
    # Set owner and basic permissions (when executed as root, target file is in user home directory)
    chown "$CURRENT_USER":"$(id -g -n "$CURRENT_USER")" "$file" || log_warn "Failed to set file ownership: $file"
    chmod 644 "$file" || log_warn "Failed to set file permissions: $file" # User read-write, group and others read
    
    return 0
}

# Generate new configuration
generate_new_config() {
    echo
    log_warn "Machine code reset option"
    
    # Use menu selection function to ask user if they want to reset machine code
    select_menu_option "Do you need to reset machine code? (Normally, modifying JS files is sufficient):" "No reset - Only modify JS files|Reset - Modify both configuration file and machine code" 0
    reset_choice=$?
    
    # Record log for debugging
    echo "[INPUT_DEBUG] Machine code reset option selection: $reset_choice" >> "$LOG_FILE"
    
    # Ensure configuration file directory exists
    mkdir -p "$(dirname "$STORAGE_FILE")"
    chown "$CURRENT_USER":"$(id -g -n "$CURRENT_USER")" "$(dirname "$STORAGE_FILE")" || log_warn "Failed to set configuration directory ownership: $(dirname "$STORAGE_FILE")"
    chmod 755 "$(dirname "$STORAGE_FILE")" || log_warn "Failed to set configuration directory permissions: $(dirname "$STORAGE_FILE")"

    # Handle user selection - index 0 corresponds to "No reset" option, index 1 corresponds to "Reset" option
    if [ "$reset_choice" = "1" ]; then
        log_info "You selected to reset machine code"
        
        # Check if configuration file exists
        if [ -f "$STORAGE_FILE" ]; then
            log_info "Found existing configuration file: $STORAGE_FILE"
            
            # Backup existing configuration
            if ! backup_config; then # If backup fails, don't continue modification
                 log_error "Configuration file backup failed, aborting machine code reset."
                 return 1 # Return error status
            fi
            
            # Generate and set new device IDs
            local new_device_id=$(generate_uuid)
            local new_machine_id=$(generate_uuid) # Using UUID as Machine ID is more common
            # 🔧 New: serviceMachineId (for storage.serviceMachineId)
            local new_service_machine_id=$(generate_uuid)
            # 🔧 New: firstSessionDate (reset first session date)
            local new_first_session_date=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
            # 🔧 New: macMachineId and sqmId
            local new_mac_machine_id=$(openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | xxd -p | tr -d '\n')
            local new_sqm_id="{$(generate_uuid | tr '[:lower:]' '[:upper:]')}"

            log_info "Setting new device and machine IDs..."
            log_debug "New device ID: $new_device_id"
            log_debug "New machine ID: $new_machine_id"
            log_debug "New serviceMachineId: $new_service_machine_id"
            log_debug "New firstSessionDate: $new_first_session_date"

            # Modify configuration file
            # 🔧 Fix: Add storage.serviceMachineId, telemetry.firstSessionDate, telemetry.macMachineId, telemetry.sqmId
            local config_success=true
            modify_or_add_config "deviceId" "$new_device_id" "$STORAGE_FILE" || config_success=false
            modify_or_add_config "machineId" "$new_machine_id" "$STORAGE_FILE" || config_success=false
            modify_or_add_config "telemetry.machineId" "$new_machine_id" "$STORAGE_FILE" || config_success=false
            modify_or_add_config "telemetry.macMachineId" "$new_mac_machine_id" "$STORAGE_FILE" || config_success=false
            modify_or_add_config "telemetry.devDeviceId" "$new_device_id" "$STORAGE_FILE" || config_success=false
            modify_or_add_config "telemetry.sqmId" "$new_sqm_id" "$STORAGE_FILE" || config_success=false
            modify_or_add_config "storage.serviceMachineId" "$new_service_machine_id" "$STORAGE_FILE" || config_success=false
            modify_or_add_config "telemetry.firstSessionDate" "$new_first_session_date" "$STORAGE_FILE" || config_success=false

            if [ "$config_success" = true ]; then
            log_info "All identifiers in configuration file modified successfully"
            log_info "📋 [Details] Updated the following identifiers:"
            echo "   🔹 deviceId: ${new_device_id:0:16}..."
            echo "   🔹 machineId: ${new_machine_id:0:16}..."
            echo "   🔹 macMachineId: ${new_mac_machine_id:0:16}..."
            echo "   🔹 sqmId: $new_sqm_id"
            echo "   🔹 serviceMachineId: $new_service_machine_id"
            echo "   🔹 firstSessionDate: $new_first_session_date"

                # 🔧 New: Modify machineid file
                log_info "🔧 [machineid] Modifying machineid file..."
                local machineid_file_path="$HOME/.config/Cursor/machineid"
                if [ -f "$machineid_file_path" ]; then
                    # Backup original machineid file
                    local machineid_backup="$BACKUP_DIR/machineid.backup_$(date +%Y%m%d_%H%M%S)"
                    cp "$machineid_file_path" "$machineid_backup" 2>/dev/null && \
                        log_info "💾 [Backup] machineid file backed up: $machineid_backup"
                fi
                # Write new serviceMachineId to machineid file
                if echo -n "$new_service_machine_id" > "$machineid_file_path" 2>/dev/null; then
                    log_info "✅ [machineid] machineid file modification successful: $new_service_machine_id"
                    # Set machineid file to read-only
                    chmod 444 "$machineid_file_path" 2>/dev/null && \
                        log_info "🔒 [Protection] machineid file set to read-only"
                else
                    log_warn "⚠️  [machineid] machineid file modification failed"
                    log_info "💡 [Tip] You can manually modify file: $machineid_file_path"
                fi

                # 🔧 New: Modify .updaterId file (updater device identifier)
                log_info "🔧 [updaterId] Modifying .updaterId file..."
                local updater_id_file_path="$HOME/.config/Cursor/.updaterId"
                if [ -f "$updater_id_file_path" ]; then
                    # Backup original .updaterId file
                    local updater_id_backup="$BACKUP_DIR/.updaterId.backup_$(date +%Y%m%d_%H%M%S)"
                    cp "$updater_id_file_path" "$updater_id_backup" 2>/dev/null && \
                        log_info "💾 [Backup] .updaterId file backed up: $updater_id_backup"
                fi
                # Generate new updaterId (UUID format)
                local new_updater_id=$(generate_uuid)
                if echo -n "$new_updater_id" > "$updater_id_file_path" 2>/dev/null; then
                    log_info "✅ [updaterId] .updaterId file modification successful: $new_updater_id"
                    # Set .updaterId file to read-only
                    chmod 444 "$updater_id_file_path" 2>/dev/null && \
                        log_info "🔒 [Protection] .updaterId file set to read-only"
                else
                    log_warn "⚠️  [updaterId] .updaterId file modification failed"
                    log_info "💡 [Tip] You can manually modify file: $updater_id_file_path"
                fi
            else
                log_error "Failed to modify some identifiers in configuration file"
                # Note: Even if failed, backup still exists, but configuration file may have been partially modified
                return 1 # Return error status
            fi
        else
            log_warn "Configuration file '$STORAGE_FILE' not found, unable to reset machine code. This is normal if this is a first-time installation."
            # Even if file does not exist, consider this step (not executed) as "successful", allow to continue
        fi
    else
        log_info "You selected not to reset machine code, will only modify JS files"
        
        # Check if configuration file exists and backup (if exists)
        if [ -f "$STORAGE_FILE" ]; then
            log_info "Found existing configuration file: $STORAGE_FILE"
            if ! backup_config; then
                 log_error "Configuration file backup failed, aborting operation."
                 return 1 # Return error status
            fi
        else
            log_warn "Configuration file '$STORAGE_FILE' not found, skipping backup."
        fi
    fi
    
    echo
    log_info "Configuration processing completed"
    return 0 # Explicitly return success
}

# Find Cursor JS files
find_cursor_js_files() {
    log_info "Searching for Cursor JS files..."
    
    local js_files=()
    local found=false
    
    # Ensure CURSOR_RESOURCES is set
    if [ -z "$CURSOR_RESOURCES" ] || [ ! -d "$CURSOR_RESOURCES" ]; then
        log_error "Cursor resource directory not found or invalid ($CURSOR_RESOURCES), cannot search for JS files."
        return 1
    fi

    log_debug "Searching for JS files in resource directory: $CURSOR_RESOURCES"
    
    # Recursively search for specific JS files in resource directory
    # Note: These patterns may need to be updated based on Cursor version
    local js_patterns=(
        "resources/app/out/vs/workbench/api/node/extensionHostProcess.js"
        "resources/app/out/main.js"
        "resources/app/out/vs/code/node/cliProcessMain.js"
        # Add other possible path patterns
        "app/out/vs/workbench/api/node/extensionHostProcess.js" # If resource directory is parent of app
        "app/out/main.js"
        "app/out/vs/code/node/cliProcessMain.js"
    )
    
    for pattern in "${js_patterns[@]}"; do
        # Use find to search for full paths under CURSOR_RESOURCES
        local files=$(find "$CURSOR_RESOURCES" -path "*/$pattern" -type f 2>/dev/null)
        if [ -n "$files" ]; then
            while IFS= read -r file; do
                # Check if file has already been added
                if [[ ! " ${js_files[@]} " =~ " ${file} " ]]; then
                    log_info "Found JS file: $file"
                    js_files+=("$file")
                    found=true
                fi
            done <<< "$files"
        fi
    done
    
    # If still not found, try more general search (may have false positives)
    if [ "$found" = false ]; then
        log_warn "JS files not found in standard path patterns, attempting broader search in resource directory '$CURSOR_RESOURCES'..."
        # Find JS files containing specific keywords
        local files=$(find "$CURSOR_RESOURCES" -name "*.js" -type f -exec grep -lE 'IOPlatformUUID|x-cursor-checksum|getMachineId' {} \; 2>/dev/null)
        if [ -n "$files" ]; then
            while IFS= read -r file; do
                 if [[ ! " ${js_files[@]} " =~ " ${file} " ]]; then
                     log_info "Found possible JS file via keywords: $file"
                     js_files+=("$file")
                     found=true
                 fi
            done <<< "$files"
        else
             log_warn "Unable to find JS files via keywords in resource directory '$CURSOR_RESOURCES'."
        fi
    fi

    if [ "$found" = false ]; then
        log_error "No modifiable JS files found in resource directory '$CURSOR_RESOURCES'."
        log_error "Please check if Cursor installation is complete, or if JS path patterns in script need updating."
        return 1
    fi
    
    # Deduplicate (theoretically handled above, but just in case)
    IFS=" " read -r -a CURSOR_JS_FILES <<< "$(echo "${js_files[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ')"
    
    log_info "Found ${#CURSOR_JS_FILES[@]} unique JS file(s) to process."
    return 0
}

# Modify Cursor JS files
# 🔧 Modify Cursor kernel JS files for device identification bypass (Enhanced Hook solution)
# Solution A: someValue placeholder replacement - stable anchor, doesn't depend on obfuscated function names
# Solution B: Deep Hook injection - intercept all device identifier generation from bottom layer
# Solution C: Module.prototype.require hijacking - intercept child_process, crypto, os and other modules
modify_cursor_js_files() {
    log_info "🔧 [Kernel Modification] Starting to modify Cursor kernel JS files for device identification bypass..."
    log_info "💡 [Solution] Using enhanced Hook solution: deep module hijacking + someValue replacement"

    # First find JS files that need to be modified
    if ! find_cursor_js_files; then
        return 1
    fi

    if [ ${#CURSOR_JS_FILES[@]} -eq 0 ]; then
        log_error "JS file list is empty, cannot continue modification."
        return 1
    fi

    # Generate new device identifiers (use fixed format to ensure compatibility)
    local new_uuid=$(generate_uuid)
    local machine_id=$(openssl rand -hex 32)
    local device_id=$(generate_uuid)
    local mac_machine_id=$(openssl rand -hex 32)
    local sqm_id="{$(generate_uuid | tr '[:lower:]' '[:upper:]')}"
    local session_id=$(generate_uuid)
    local first_session_date=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
    local mac_address="00:11:22:33:44:55"

    log_info "🔑 [Generate] Generated new device identifiers"
    log_info "   machineId: ${machine_id:0:16}..."
    log_info "   deviceId: ${device_id:0:16}..."
    log_info "   macMachineId: ${mac_machine_id:0:16}..."
    log_info "   sqmId: $sqm_id"

    # Delete old configuration and regenerate each time to ensure new device identifiers
    local ids_config_path="$HOME/.cursor_ids.json"
    if [ -f "$ids_config_path" ]; then
        rm -f "$ids_config_path"
        log_info "🗑️  [Cleanup] Deleted old ID configuration file"
    fi
    cat > "$ids_config_path" << EOF
{
  "machineId": "$machine_id",
  "macMachineId": "$mac_machine_id",
  "devDeviceId": "$device_id",
  "sqmId": "$sqm_id",
  "macAddress": "$mac_address",
  "createdAt": "$first_session_date"
}
EOF
    chown "$CURRENT_USER":"$(id -g -n "$CURRENT_USER")" "$ids_config_path" 2>/dev/null || true
    log_info "💾 [Save] New ID configuration saved to: $ids_config_path"

    local modified_count=0
    local file_modification_status=()

    # Process each file: create original backup or restore from original backup
    for file in "${CURSOR_JS_FILES[@]}"; do
        log_info "📝 [Processing] Processing: $(basename "$file")"

        if [ ! -f "$file" ]; then
            log_error "File does not exist: $file, skipping processing."
            file_modification_status+=("'$(basename "$file")': Not Found")
            continue
        fi

        # Create backup directory
        local backup_dir="$(dirname "$file")/backups"
        mkdir -p "$backup_dir" 2>/dev/null || true

        local file_name=$(basename "$file")
        local original_backup="$backup_dir/$file_name.original"

        # If original backup doesn't exist, create it first
        if [ ! -f "$original_backup" ]; then
            # Check if current file has been modified
            if grep -q "__cursor_patched__" "$file" 2>/dev/null; then
                log_warn "⚠️  [Warning] File has been modified but no original backup exists, will use current version as base"
            fi
            cp "$file" "$original_backup"
            chown "$CURRENT_USER":"$(id -g -n "$CURRENT_USER")" "$original_backup" 2>/dev/null || true
            chmod 444 "$original_backup" 2>/dev/null || true
            log_info "✅ [Backup] Original backup created successfully: $file_name"
        else
            # Restore from original backup to ensure clean injection each time
            log_info "🔄 [Restore] Restoring from original backup: $file_name"
            cp "$original_backup" "$file"
        fi

        # Create timestamped backup (record state before each modification)
        local backup_file="$backup_dir/$file_name.backup_$(date +%Y%m%d_%H%M%S)"
        if ! cp "$file" "$backup_file"; then
            log_error "Unable to create file backup: $file"
            file_modification_status+=("'$(basename "$file")': Backup Failed")
            continue
        fi
        chown "$CURRENT_USER":"$(id -g -n "$CURRENT_USER")" "$backup_file" 2>/dev/null || true
        chmod 444 "$backup_file" 2>/dev/null || true

        chmod u+w "$file" || {
            log_error "Unable to modify file permissions (write): $file"
            file_modification_status+=("'$(basename "$file")': Permission Error")
            continue
        }

        local replaced=false

        # ========== Solution A: someValue placeholder replacement (stable anchor) ==========
        # Important note:
        # In current Cursor's main.js, placeholders usually appear as string literals, e.g.:
        #   this.machineId="someValue.machineId"
        # If we directly replace someValue.machineId with "\"<real_value>\"", it will form ""<real_value>"" causing JS syntax error.
        # Therefore, we prioritize replacing complete string literals (including outer quotes), then fallback to replacing placeholders without quotes.
        if grep -q 'someValue\.machineId' "$file"; then
            sed -i "s/\"someValue\.machineId\"/\"${machine_id}\"/g" "$file"
            sed -i "s/'someValue\.machineId'/\"${machine_id}\"/g" "$file"
            sed -i "s/someValue\.machineId/\"${machine_id}\"/g" "$file"
            log_info "   ✓ [Solution A] Replaced someValue.machineId"
            replaced=true
        fi

        if grep -q 'someValue\.macMachineId' "$file"; then
            sed -i "s/\"someValue\.macMachineId\"/\"${mac_machine_id}\"/g" "$file"
            sed -i "s/'someValue\.macMachineId'/\"${mac_machine_id}\"/g" "$file"
            sed -i "s/someValue\.macMachineId/\"${mac_machine_id}\"/g" "$file"
            log_info "   ✓ [Solution A] Replaced someValue.macMachineId"
            replaced=true
        fi

        if grep -q 'someValue\.devDeviceId' "$file"; then
            sed -i "s/\"someValue\.devDeviceId\"/\"${device_id}\"/g" "$file"
            sed -i "s/'someValue\.devDeviceId'/\"${device_id}\"/g" "$file"
            sed -i "s/someValue\.devDeviceId/\"${device_id}\"/g" "$file"
            log_info "   ✓ [Solution A] Replaced someValue.devDeviceId"
            replaced=true
        fi

        if grep -q 'someValue\.sqmId' "$file"; then
            sed -i "s/\"someValue\.sqmId\"/\"${sqm_id}\"/g" "$file"
            sed -i "s/'someValue\.sqmId'/\"${sqm_id}\"/g" "$file"
            sed -i "s/someValue\.sqmId/\"${sqm_id}\"/g" "$file"
            log_info "   ✓ [Solution A] Replaced someValue.sqmId"
            replaced=true
        fi

        if grep -q 'someValue\.sessionId' "$file"; then
            sed -i "s/\"someValue\.sessionId\"/\"${session_id}\"/g" "$file"
            sed -i "s/'someValue\.sessionId'/\"${session_id}\"/g" "$file"
            sed -i "s/someValue\.sessionId/\"${session_id}\"/g" "$file"
            log_info "   ✓ [Solution A] Replaced someValue.sessionId"
            replaced=true
        fi

        if grep -q 'someValue\.firstSessionDate' "$file"; then
            sed -i "s/\"someValue\.firstSessionDate\"/\"${first_session_date}\"/g" "$file"
            sed -i "s/'someValue\.firstSessionDate'/\"${first_session_date}\"/g" "$file"
            sed -i "s/someValue\.firstSessionDate/\"${first_session_date}\"/g" "$file"
            log_info "   ✓ [Solution A] Replaced someValue.firstSessionDate"
            replaced=true
        fi

        # ========== Solution B: Enhanced deep Hook injection ==========
        local inject_code='// ========== Cursor Hook Injection Start ==========
;(async function(){/*__cursor_patched__*/
"use strict";
if(globalThis.__cursor_patched__)return;

// ESM compatibility: ensure available require (some versions of main.js may be pure ESM, require not guaranteed)
var __require__=typeof require==="function"?require:null;
if(!__require__){
    try{
        var __m__=await import("module");
        __require__=__m__.createRequire(import.meta.url);
    }catch(e){
        // Exit directly when unable to get require, avoid affecting main process startup
        return;
    }
}

globalThis.__cursor_patched__=true;

var __ids__={
    machineId:"'"$machine_id"'",
    macMachineId:"'"$mac_machine_id"'",
    devDeviceId:"'"$device_id"'",
    sqmId:"'"$sqm_id"'",
    macAddress:"'"$mac_address"'"
};

globalThis.__cursor_ids__=__ids__;

var Module=__require__("module");
var _origReq=Module.prototype.require;
var _hooked=new Map();

Module.prototype.require=function(id){
    var result=_origReq.apply(this,arguments);
    if(_hooked.has(id))return _hooked.get(id);
    var hooked=result;

    if(id==="child_process"){
        var _origExecSync=result.execSync;
        result.execSync=function(cmd,opts){
            var cmdStr=String(cmd).toLowerCase();
            if(cmdStr.includes("machine-id")||cmdStr.includes("hostname")){
                return Buffer.from(__ids__.machineId.substring(0,32));
            }
            return _origExecSync.apply(this,arguments);
        };
        hooked=result;
    }
    else if(id==="os"){
        result.networkInterfaces=function(){
            return{"eth0":[{address:"192.168.1.100",netmask:"255.255.255.0",family:"IPv4",mac:__ids__.macAddress,internal:false}]};
        };
        hooked=result;
    }
    else if(id==="crypto"){
        var _origCreateHash=result.createHash;
        var _origRandomUUID=result.randomUUID;
        result.createHash=function(algo){
            var hash=_origCreateHash.apply(this,arguments);
            if(algo.toLowerCase()==="sha256"){
                var _origDigest=hash.digest.bind(hash);
                var _origUpdate=hash.update.bind(hash);
                var inputData="";
                hash.update=function(data,enc){inputData+=String(data);return _origUpdate(data,enc);};
                hash.digest=function(enc){
                    if(inputData.includes("machine-id")||(inputData.length>=32&&inputData.length<=40)){
                        return enc==="hex"?__ids__.machineId:Buffer.from(__ids__.machineId,"hex");
                    }
                    return _origDigest(enc);
                };
            }
            return hash;
        };
        if(_origRandomUUID){
            var uuidCount=0;
            result.randomUUID=function(){
                uuidCount++;
                if(uuidCount<=2)return __ids__.devDeviceId;
                return _origRandomUUID.apply(this,arguments);
            };
        }
        hooked=result;
    }
    else if(id==="@vscode/deviceid"){
        hooked={...result,getDeviceId:async function(){return __ids__.devDeviceId;}};
    }

    if(hooked!==result)_hooked.set(id,hooked);
    return hooked;
};

console.log("[Cursor ID Modifier] Enhanced Hook Activated - Official Account【煎饼果子卷AI】");
})();
// ========== Cursor Hook Injection End ==========

'

        # Inject code after copyright notice
        local temp_file=$(mktemp)
        if grep -q '\*/' "$file"; then
            awk -v inject="$inject_code" '
            /\*\// && !injected {
                print
                print ""
                print inject
                injected = 1
                next
            }
            { print }
            ' "$file" > "$temp_file"
            log_info "   ✓ [Solution B] Enhanced Hook code injected (after copyright notice)"
        else
            echo "$inject_code" > "$temp_file"
            cat "$file" >> "$temp_file"
            log_info "   ✓ [Solution B] Enhanced Hook code injected (at file beginning)"
        fi

        if mv "$temp_file" "$file"; then
            if [ "$replaced" = true ]; then
                log_info "✅ [Success] Enhanced hybrid solution modification successful (someValue replacement + deep Hook)"
            else
                log_info "✅ [Success] Enhanced Hook modification successful"
            fi
            ((modified_count++))
            file_modification_status+=("'$(basename "$file")': Success")

            chmod u-w,go-w "$file" 2>/dev/null || true
            chown "$CURRENT_USER":"$(id -g -n "$CURRENT_USER")" "$file" 2>/dev/null || true
        else
            log_error "Hook injection failed (unable to move temporary file)"
            rm -f "$temp_file"
            file_modification_status+=("'$(basename "$file")': Inject Failed")
            cp "$original_backup" "$file" 2>/dev/null || true
        fi

    done

    log_info "📊 [Statistics] JS file processing status summary:"
    for status in "${file_modification_status[@]}"; do
        log_info "   - $status"
    done

    if [ "$modified_count" -eq 0 ]; then
        log_error "❌ [Failed] Unable to successfully modify any JS files."
        return 1
    fi

    log_info "🎉 [Complete] Successfully modified $modified_count JS file(s)"
    log_info "💡 [Description] Using enhanced Hook solution:"
    log_info "   • Solution A: someValue placeholder replacement (stable anchor, cross-version compatible)"
    log_info "   • Solution B: Deep module hijacking (child_process, crypto, os, @vscode/*)"
    log_info "📁 [Configuration] ID configuration file: $ids_config_path"
    return 0
}

# Disable auto-updates
disable_auto_update() {
    log_info "Attempting to disable Cursor auto-updates..."
    
    # Find possible update configuration files
    local update_configs=()
    # In user configuration directory
    if [ -d "$CURSOR_CONFIG_DIR" ]; then
        update_configs+=("$CURSOR_CONFIG_DIR/update-config.json")
        update_configs+=("$CURSOR_CONFIG_DIR/settings.json") # Some settings may be here
    fi
    # In installation directory (if resource directory is determined)
    if [ -n "$CURSOR_RESOURCES" ] && [ -d "$CURSOR_RESOURCES" ]; then
        update_configs+=("$CURSOR_RESOURCES/resources/app-update.yml")
         update_configs+=("$CURSOR_RESOURCES/app-update.yml") # Possible location
    fi
     # In standard installation directory
     if [ -d "$INSTALL_DIR" ]; then
          update_configs+=("$INSTALL_DIR/resources/app-update.yml")
          update_configs+=("$INSTALL_DIR/app-update.yml")
     fi
     # $HOME/.local/share
     update_configs+=("$HOME/.local/share/cursor/update-config.json")


    local disabled_count=0
    
    # Process JSON configuration files
    local json_config_pattern='update-config.json|settings.json'
    for config in "${update_configs[@]}"; do
       if [[ "$config" =~ $json_config_pattern ]] && [ -f "$config" ]; then
           log_info "Found possible update configuration file: $config"
           
           # Backup
           cp "$config" "${config}.bak_$(date +%Y%m%d%H%M%S)" 2>/dev/null
           
           # Try to modify JSON (if exists and is settings.json)
           if [[ "$config" == *settings.json ]]; then
               # Try to add or modify "update.mode": "none"
                if grep -q '"update.mode"' "$config"; then
                    sed -i 's/"update.mode":[[:space:]]*"[^"]*"/"update.mode": "none"/' "$config" || log_warn "Failed to modify update.mode in settings.json"
                elif grep -q "}" "$config"; then # Try to inject
                     sed -i '$ s/}/,\n    "update.mode": "none"\n}/' "$config" || log_warn "Failed to inject update.mode to settings.json"
                else
                    log_warn "Unable to modify settings.json to disable updates (structure unknown)"
                fi
                # Ensure permissions are correct
                 chown "$CURRENT_USER":"$(id -g -n "$CURRENT_USER")" "$config" || log_warn "Failed to set ownership: $config"
                 chmod 644 "$config" || log_warn "Failed to set permissions: $config"
                 ((disabled_count++))
                 log_info "Attempted to set 'update.mode' to 'none' in '$config'"
           elif [[ "$config" == *update-config.json ]]; then
                # Directly overwrite update-config.json
                echo '{"autoCheck": false, "autoDownload": false}' > "$config"
                chown "$CURRENT_USER":"$(id -g -n "$CURRENT_USER")" "$config" || log_warn "Failed to set ownership: $config"
                chmod 644 "$config" || log_warn "Failed to set permissions: $config"
                ((disabled_count++))
                log_info "Overwritten update configuration file: $config"
            fi
       fi
    done

    # Process YAML configuration files
     local yml_config_pattern='app-update.yml'
     for config in "${update_configs[@]}"; do
        if [[ "$config" =~ $yml_config_pattern ]] && [ -f "$config" ]; then
            log_info "Found possible update configuration file: $config"
            # Backup
            cp "$config" "${config}.bak_$(date +%Y%m%d%H%M%S)" 2>/dev/null
            # Clear or modify content (for simplicity, directly clear or write disable marker)
            echo "# Automatic updates disabled by script $(date)" > "$config"
            # echo "provider: generic" > "$config" # Or try to modify provider
            # echo "url: http://127.0.0.1" >> "$config"
            chmod 444 "$config" # Set to read-only
            ((disabled_count++))
            log_info "Modified/cleared update configuration file: $config"
        fi
     done

    # Try to find updater executable and disable (rename or remove permissions)
    local updater_paths=()
     if [ -n "$CURSOR_RESOURCES" ] && [ -d "$CURSOR_RESOURCES" ]; then
        updater_paths+=($(find "$CURSOR_RESOURCES" -name "updater" -type f -executable 2>/dev/null))
        updater_paths+=($(find "$CURSOR_RESOURCES" -name "CursorUpdater" -type f -executable 2>/dev/null)) # macOS style?
     fi
      if [ -d "$INSTALL_DIR" ]; then
          updater_paths+=($(find "$INSTALL_DIR" -name "updater" -type f -executable 2>/dev/null))
          updater_paths+=($(find "$INSTALL_DIR" -name "CursorUpdater" -type f -executable 2>/dev/null))
      fi
      updater_paths+=("$HOME/.config/Cursor/updater") # Old location?

    for updater in "${updater_paths[@]}"; do
        if [ -f "$updater" ] && [ -x "$updater" ]; then
            log_info "Found updater: $updater"
            local bak_updater="${updater}.bak_$(date +%Y%m%d%H%M%S)"
            if mv "$updater" "$bak_updater"; then
                 log_info "Renamed updater to: $bak_updater"
                 ((disabled_count++))
            else
                 log_warn "Failed to rename updater: $updater, attempting to remove execute permissions..."
                 if chmod a-x "$updater"; then
                      log_info "Removed updater execute permissions: $updater"
                      ((disabled_count++))
                 else
                     log_error "Unable to disable updater: $updater"
                 fi
            fi
        # elif [ -d "$updater" ]; then # If it's a directory, try to disable
        #     log_info "Found updater directory: $updater"
        #     touch "${updater}.disabled_by_script"
        #     log_info "Marked updater directory as disabled: $updater"
        #     ((disabled_count++))
        fi
    done
    
    if [ "$disabled_count" -eq 0 ]; then
        log_warn "Unable to find or disable any known auto-update mechanisms."
        log_warn "If Cursor still auto-updates, you may need to manually find and disable related files or settings."
    else
        log_info "Successfully disabled or attempted to disable $disabled_count auto-update related files/programs."
    fi
     return 0 # Even if not found, consider function execution successful
}

# New: Universal menu selection function
select_menu_option() {
    local prompt="$1"
    IFS='|' read -ra options <<< "$2"
    local default_index=${3:-0}
    local selected_index=$default_index
    local key_input
    local cursor_up=$'\e[A' # More standard ANSI code
    local cursor_down=$'\e[B'
    local enter_key=$'\n'

    # Hide cursor
    tput civis
    # Clear possible old menu lines (assuming menu has at most N lines)
    local num_options=${#options[@]}
    for ((i=0; i<num_options+1; i++)); do echo -e "\033[K"; done # Clear line
     tput cuu $((num_options + 1)) # Move cursor back to top


    # Display prompt information
    echo -e "$prompt"
    
    # Draw menu function
    draw_menu() {
        # Move cursor to one line below menu start line
        tput cud 1 
        for i in "${!options[@]}"; do
             tput el # Clear current line
            if [ $i -eq $selected_index ]; then
                echo -e " ${GREEN}►${NC} ${options[$i]}"
            else
                echo -e "   ${options[$i]}"
            fi
        done
         # Move cursor back below prompt line
        tput cuu "$num_options"
    }
    
    # First display menu
    draw_menu

    # Loop to handle keyboard input
    while true; do
        # Read key press (use -sn1 or -sn3 depending on system's handling of arrow keys)
        # -N 1 reads single character, may need multiple reads for arrow keys
        # -N 3 reads 3 characters at once, usually for arrow keys
        read -rsn1 key_press_1 # Read first character
         if [[ "$key_press_1" == $'\e' ]]; then # If ESC, read subsequent characters
             read -rsn2 key_press_2 # Read '[' and A/B
             key_input="$key_press_1$key_press_2"
         elif [[ "$key_press_1" == "" ]]; then # If Enter
             key_input=$enter_key
         else
             key_input="$key_press_1" # Other keys
         fi

        # Detect key press
        case "$key_input" in
            # Up arrow key
            "$cursor_up")
                if [ $selected_index -gt 0 ]; then
                    ((selected_index--))
                    draw_menu
                fi
                ;;
            # Down arrow key
            "$cursor_down")
                if [ $selected_index -lt $((${#options[@]}-1)) ]; then
                    ((selected_index++))
                    draw_menu
                fi
                ;;
            # Enter key
            "$enter_key")
                 # Clear menu area
                 tput cud 1 # Move down one line to start clearing
                 for i in "${!options[@]}"; do tput el; tput cud 1; done
                 tput cuu $((num_options + 1)) # Move back to prompt line
                 tput el # Clear prompt line itself
                 echo -e "$prompt ${GREEN}${options[$selected_index]}${NC}" # Display final selection

                 # Restore cursor
                 tput cnorm
                 # Return selected index
                 return $selected_index
                ;;
             *)
                 # Ignore other keys
                 ;;
        esac
    done
}

# New: Cursor initialization cleanup function
cursor_initialize_cleanup() {
    log_info "Executing Cursor initialization cleanup..."
    # CURSOR_CONFIG_DIR is globally defined in script: $HOME/.config/Cursor
    local USER_CONFIG_BASE_PATH="$CURSOR_CONFIG_DIR/User"

    log_debug "User configuration base path: $USER_CONFIG_BASE_PATH"

    local files_to_delete=(
        "$USER_CONFIG_BASE_PATH/globalStorage/state.vscdb"
        "$USER_CONFIG_BASE_PATH/globalStorage/state.vscdb.backup"
    )
    
    local folder_to_clean_contents="$USER_CONFIG_BASE_PATH/History"
    local folder_to_delete_completely="$USER_CONFIG_BASE_PATH/workspaceStorage"

    # Delete specified files
    for file_path in "${files_to_delete[@]}"; do
        log_debug "Checking file: $file_path"
        if [ -f "$file_path" ]; then
            if rm -f "$file_path"; then
                log_info "Deleted file: $file_path"
            else
                log_error "Failed to delete file $file_path"
            fi
        else
            log_warn "File does not exist, skipping deletion: $file_path"
        fi
    done

    # Clear specified folder contents
    log_debug "Checking folder to clear contents: $folder_to_clean_contents"
    if [ -d "$folder_to_clean_contents" ]; then
        if find "$folder_to_clean_contents" -mindepth 1 -delete; then
            log_info "Cleared folder contents: $folder_to_clean_contents"
        else
            if [ -z "$(ls -A "$folder_to_clean_contents")" ]; then
                 log_info "Folder $folder_to_clean_contents is now empty."
            else
                 log_error "Failed to clear folder $folder_to_clean_contents contents (partially or completely). Please check permissions or manually delete."
            fi
        fi
    else
        log_warn "Folder does not exist, skipping clear: $folder_to_clean_contents"
    fi

    # Delete specified folder and its contents
    log_debug "Checking folder to delete completely: $folder_to_delete_completely"
    if [ -d "$folder_to_delete_completely" ]; then
        if rm -rf "$folder_to_delete_completely"; then
            log_info "Deleted folder: $folder_to_delete_completely"
        else
            log_error "Failed to delete folder $folder_to_delete_completely"
        fi
    else
        log_warn "Folder does not exist, skipping deletion: $folder_to_delete_completely"
    fi

    log_info "Cursor initialization cleanup completed."
}

# Main function
main() {
    # Initialize log file
    initialize_log
    log_info "Script starting..."
    log_info "Running user: $CURRENT_USER (script running with EUID=$EUID)"

    # Check permissions (must be early in script)
    check_permissions # Requires root permissions for installation and system file modification

    # Record system information
    log_info "System information: $(uname -a)"
    log_cmd_output "lsb_release -a 2>/dev/null || cat /etc/*release 2>/dev/null || cat /etc/issue" "System version information"
    
    clear
    # Display Logo
    echo -e "
    ██████╗██╗   ██╗██████╗ ███████╗ ██████╗ ██████╗ 
   ██╔════╝██║   ██║██╔══██╗██╔════╝██╔═══██╗██╔══██╗
   ██║     ██║   ██║██████╔╝███████╗██║   ██║██████╔╝
   ██║     ██║   ██║██╔══██╗╚════██║██║   ██║██╔══██╗
   ╚██████╗╚██████╔╝██║  ██║███████║╚██████╔╝██║  ██║
    ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝
    "
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}         Cursor Linux Startup & Modification Tool (Free)            ${NC}"
    echo -e "${YELLOW}        Follow Official Account【煎饼果子卷AI】     ${NC}"
    echo -e "${YELLOW}  Share more Cursor tips and AI knowledge (Script is free, follow the account to join group for more tips and experts)  ${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo
    echo -e "${YELLOW}⚡  [Advertisement] Official Cursor Accounts: Pro¥65 | Pro+¥265 | Ultra¥888 Exclusive account/7-day warranty, WeChat: JavaRookie666  ${NC}"
    echo
    echo -e "${YELLOW}[Tip]${NC} This tool is designed to modify Cursor to resolve potential startup issues or device restrictions."
    echo -e "${YELLOW}[Tip]${NC} It will prioritize modifying JS files and optionally reset device IDs and disable auto-updates."
    echo -e "${YELLOW}[Tip]${NC} If Cursor is not found, it will attempt to install from the '$APPIMAGE_SEARCH_DIR' directory."
    echo

    # Find Cursor path
    if ! find_cursor_path; then
        log_warn "No existing Cursor installation found in the system."
        select_menu_option "Attempt to install Cursor from AppImage file in '$APPIMAGE_SEARCH_DIR' directory?" "Yes, install Cursor|No, exit script" 0
        install_choice=$?
        
        if [ "$install_choice" -eq 0 ]; then
            if ! install_cursor_appimage; then
                log_error "Cursor installation failed, please check the logs above. Script will exit."
                exit 1
            fi
            # After successful installation, re-find paths
            if ! find_cursor_path || ! find_cursor_resources; then
                 log_error "Still unable to find Cursor executable or resource directory after installation. Please check '$INSTALL_DIR' and '/usr/local/bin/cursor'. Script exiting."
                 exit 1
            fi
            log_info "Cursor installation successful, continuing with modification steps..."
        else
            log_info "User chose not to install Cursor, script exiting."
            exit 0
        fi
    else
        # If Cursor is found, also ensure resource directory is found
        if ! find_cursor_resources; then
            log_error "Found Cursor executable ($CURSOR_PATH), but unable to locate resource directory."
            log_error "Cannot continue modifying JS files. Please check if Cursor installation is complete. Script exiting."
            exit 1
        fi
        log_info "Found installed Cursor ($CURSOR_PATH), resource directory ($CURSOR_RESOURCES)."
    fi

    # At this point, Cursor should be installed and paths are known

    # Check and close Cursor processes
    if ! check_and_kill_cursor; then
         # check_and_kill_cursor will log errors and exit internally, but just in case
         exit 1
    fi
    
    # Execute Cursor initialization cleanup
    # cursor_initialize_cleanup

    # Backup and process configuration file (machine code reset option)
    if ! generate_new_config; then
         log_error "Error occurred while processing configuration file, script aborted."
         # May need to consider rolling back JS modifications (if executed)? Currently not rolling back.
         exit 1
    fi
    
    # Modify JS files
    log_info "Modifying Cursor JS files..."
    if ! modify_cursor_js_files; then
        log_error "Error occurred during JS file modification."
        log_warn "Configuration file may have been modified, but JS file modification failed."
        log_warn "If Cursor behaves abnormally or issues persist after restart, please check logs and consider manually restoring backup or re-running the script."
        # Decide whether to continue with disabling updates? Usually recommended to continue
        # exit 1 # Or choose to exit
    else
        log_info "JS file modification successful!"
    fi
    
    # Disable auto-updates
    if ! disable_auto_update; then
        # disable_auto_update will log warnings internally, not considered fatal error
        log_warn "Encountered issues while attempting to disable auto-updates (see logs for details), but script will continue."
    fi
    
    log_info "All modification steps completed!"
    log_info "Please start Cursor to apply changes."
    
    # Display final prompt information
    echo
    echo -e "${GREEN}=====================================================${NC}"
    echo -e "${YELLOW}  Please follow Official Account【煎饼果子卷AI】for more tips and communication ${NC}"
    echo -e "${YELLOW}⚡   [Advertisement] Official Cursor Accounts: Pro¥65 | Pro+¥265 | Ultra¥888 Exclusive account/7-day warranty, WeChat: JavaRookie666  ${NC}"
    echo -e "${GREEN}=====================================================${NC}"
    echo
    
    # Record script completion information
    log_info "Script execution completed"
    echo "========== Cursor ID Modification Tool Log End $(date) ==========" >> "$LOG_FILE"
    
    # Display log file location
    echo
    log_info "Detailed log saved to: $LOG_FILE"
    echo "If you encounter issues, please provide this log file to the developer for troubleshooting"
    echo
}

# Execute main function
main

exit 0 # Ensure final return of success status code
