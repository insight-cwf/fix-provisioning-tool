#!/usr/bin/env zsh

# GitHub: @captam3rica

#
#   A script to help workaround automated enrollment issues due to DEP communication
#   failures or glitches.
#


VERSION=2.0.0


# Set exit code to 0 initially
RET=0

# Incase we need to know where the current directory is
HERE=$(/usr/bin/dirname "$0")

# Constants
JAMF_LOG="/var/log/jamf.log"
SCRIPT_NAME=$(/usr/bin/basename "$0" | /usr/bin/awk -F "." '{print $1}')
TODAY=$(date +"%Y-%m-%d")

# Log stuff
LOG_NAME="fix_provisioning_tool.log"
LOG_PATH="/Library/Logs/$LOG_NAME"


main() {
    # Run the core logic

    logging "info" ""
    logging "info" "Starting $SCRIPT_NAME log"
    logging "info" ""
    logging "info" "Script version: $VERSION"
    logging "info" "Date: $TODAY"
    logging "info" ""

    local current_user="$(get_current_user)"
    logging "info" "Current logged in user: $current_user"

    # Make the Enrollment_Log directory where we will store enrollment error logs.
    logging "info" "Creating the Enrollment_Info directory on the user's Desktop"
    local enrollment_log_dir="/Users/$current_user/Desktop/Enrollment_Logs"
    create_directory "$enrollment_log_dir"

    # Set ownership on the enrollment log directory
    set_ownership "$current_user" "$enrollment_log_dir"

    logging "info" "Checking for a valid internet connection ..."
    internet_status="$(check_internet_connection)"

    # Make sure that a good internet connection is found before continuing.
    if [[ "$internet_status" = true ]]; then

        logging "info" "Looking for $JAMF_LOG"

        # Look to see if the jamf log is present before we go any further.
        if [[ -f "$JAMF_LOG" ]]; then
            jamf_log_status=true
            logging "" "Found the jamf.log ..."
            logging "info" "Copying jamf.log to the Enrollment_Log directory ..."
            /bin/cp -a "$JAMF_LOG" "$enrollment_log_dir"

            # Checking device signature errors
            logging "info" "Checking for device signature errors ..."
            device_sig_err_status="$(check_for_device_signature_errors "$JAMF_LOG")"

            if [[ "$device_sig_err_status" = true ]]; then
                # Check to see if any device signature errors were found in the jamf.log

                # Get all of the system profiles on this Mac.
                system_profiles_list="$(return_system_profiles "configuration")"

                # Check to see if any configuration profiles are returned
                if [[ "$system_profiles_list" == *"no configuration profiles"* ]]; then
                    logging "warning" "No configuration profiles found on this Mac ..."

                else
                    logging "" "Attempting to remove the Jamf Framework ..."
                    jamf_framework_removal_status="$(remove_framework)"

                    /bin/sleep 3

                    while [[ -n "$(return_profile_uuid $system_profiles_list 'MDM Profile')" ]]; do
                        # Make sure that the MDM Profile is gone before moving on.
                        logging "" "The MDM Profile is still present on the Mac ..."
                        logging "" "Waiting for it to be removed before continuing ..."
                        /bin/sleep 1

                        # Pull the profiles list again
                        system_profiles_list="$(return_system_profiles "configuration")"

                    done

                    user_profiles_list="$(return_user_profiles "$current_user")"

                    if [[ "$user_profiles_list" == *"cannot be found"* ]]; then
                        logging "warning" "Configuration profiles not found for current logged in user ..."

                    else
                        builtin_ca_uuid="$(return_profile_uuid "$user_profiles_list" "CA Certificate")"
                        logging "info" "CA Cert profile UUID: $builtin_ca_uuid"
                        mdm_ca_cert_status="$(remove_configuration_profile "configuration" "$current_user" "$builtin_ca_uuid")"

                    fi

                    # Let things setting a bit.
                    /bin/sleep 5

                    logging "INFO" "Attempting to re-enroll this computer"
                    renew_enrollment="$(renew_enrollment)"

                fi

            elif [[ "$(check_jamf_enrollment_complete $JAMF_LOG)" = true ]]; then
                # If no device signatures found check to see if enrollmentComplete entry
                # is in the jamf.log
                logging "" "This looks good from a Jamf enrollment perspective."
                logging "" "It is possible that something interrupted the Mac setup after Jamf enrollment completed ..."
                jamf_enrollment_complete=true

            else
                logging "warning" "It's possible that a network disruption caused the Jamf enrollment to fail ..."
                jamf_enrollment_complete=false

            fi

        else
            # Did not find the jamf.log file

            jamf_log_status=false
            logging "info" "The Jamf log is not present on this Mac"
            logging "info" "Will try to kickoff the enrollment process ..."
            renew_enrollment="$(renew_enrollment)"

        fi


    else
        logging "warning" "We could not obtain a valid internet connection."
        logging "warning" "Please ensure that this Mac is connected to good internet signal. Then, try running this tool again ..."
    fi


    cleanup "$LOG_PATH" "$enrollment_log_dir" "$SCRIPT_NAME"

    build_notification_window "$current_user" "$device_sig_err_status" "$jamf_framework_removal_status" "$mdm_ca_cert_status" "$renew_enrollment" "$jamf_log_status" "$internet_status" "$jamf_enrollment_complete"
}


logging() {
    # Pe-pend text and print to standard output
    # Takes in a log level and log string.
    # Example: logging "INFO" "Something describing what happened."

    log_level=$(printf "$1" | /usr/bin/tr '[[:lower:]]' '[[:upper:]]')
    log_statement="$2"
    LOG_NAME="fix_provisioning_tool.log"
    LOG_PATH="/Library/Logs/$LOG_NAME"

    if [[ -z "$log_level" ]]; then
        # If the first builtin is an empty string set it to log level INFO
        log_level="INFO"
    fi

    if [[ -z "$log_statement" ]]; then
        # The statement was piped to the log function from another command.
        log_statement=""
    fi

    DATE=$(date +"[%b %d, %Y %Z %T $log_level]:")
    printf "%s %s\n" "$DATE" "$log_statement" >> "$LOG_PATH"
}


cleanup() {
    # Run cleanup routine
    #
    # Args:
    #   $1: Log path
    #   $2: Enrollment log directory
    #   $3: Script name

    logging "info" ""
    logging "info" "Ending $3 log"
    logging "info" ""

    logging "info" "Copying the $1 ..."
    /bin/cp -a "$1" "$2"

    # Remove the fix-provisioning-tool log
    /bin/rm -rf "$1"
}


get_current_user() {
    # Return the current user
    printf '%s' "show State:/Users/ConsoleUser" | \
        /usr/sbin/scutil | \
        /usr/bin/awk '/Name :/ && ! /loginwindow/ {print $3}'
}


create_directory(){
    # Create a directory at the provided path.
    local path_input="$1"
    if [[ ! -d "$path_input" ]]; then
        # Determine if the path_input does not exist. If it doesn't, create it.
        /bin/mkdir -p "$path_input"
    else
        # Log that the path_input already exists.
        logging "" "$path_input already exists."
    fi
}


all_network_devices () {
    # Return an array of all network device interfaces
    # Get network device interfaces
    /usr/sbin/networksetup -listallhardwareports | \
            /usr/bin/grep "Device" | \
            /usr/bin/awk -F ":" '{print $2}' | \
            /usr/bin/sed -e 's/^[[ \t]]*//'
}


active_network_devices () {
    # Find the active network interfaces

    # Initialize counter
    local count=0
    device_list="$(all_network_devices)"
    for device in $device_list; do
        # Loop through network hardware devices
        # Get the hardware port for a given network device
        HARDWARE_PORT=$(/usr/sbin/networksetup -listallhardwareports | \
            /usr/bin/grep -B 1 "$device" | \
            /usr/bin/grep "Hardware Port" | \
            /usr/bin/awk -F ":" '{ print $2 }' | \
            sed -e 's/^[[ \t]]*//')

        # See if given device has an active connection
        # Return 0 for active or 1 for inactive
        /sbin/ifconfig "$device" 2>/dev/null | \
            /usr/bin/grep "status: active" > /dev/null 2>&1

        # Outcome of previous command
        local response="$?"

        # Increment the counter
        local count=$((count+1))

        if [[ "$response" -eq 0 ]]; then
            # If network device is active
            printf "%s\n" "$HARDWARE_PORT"
            break
        fi
    done
}


check_internet_connection() {
    # Check the internet connection to make sure we can get out.
    local connection_status=""

    /sbin/ping -q -c 1 -W 1 8.8.8.8 >/dev/null
    ret="$?"

    i=1
    while [[ "$RET" -ne 0 ]]; do
        # We are waiting for a valid internet connection
        logging "info" "Waiting for a valid internet connection ..."
        /bin/sleep 1
        /sbin/ping 8.8.8.8
        RET="$?"

        i=$((i=1))
        if [[ "$i" -eq 12 ]]; then
            logging "warning" "We could not establish a valid internet connection ..."
            connection_status=false
            break
        fi
    done

    if [[ "$RET" -eq 0 ]]; then
        logging "info" "Found a valid internet connection ..."
        connection_status=true
    fi
    # Return connection_status
    printf "%s\n" "$connection_status"
}


return_ip_address () {
    # Return the IP Address assigned to a given Hardware Interface

    # Return the Hardware Port of the active interface.
    hwp="$(active_network_devices)"

    /usr/sbin/networksetup -getinfo "$hwp" | \
        /usr/bin/grep "^IP address:" | \
        /usr/bin/awk -F ":" '{print $2}' | \
        /usr/bin/sed -e 's/^[[ \t]]*//'
}


return_serial_number () {
    # Get the device serial number
    /usr/sbin/system_profiler SPHardwareDataType | \
        /usr/bin/awk '/Serial\ Number\ \(system\)/ {print $NF}'
}


return_computer_name () {
    # Get the computer name
    /usr/sbin/scutil --get ComputerName
}


set_ownership() {
    # Set ownership for folder of directory
    # Parameters
    #   $1: user
    #   $2: folder or directory - must be full path
    #
    local user="$1"
    local path_to_item="$2"
    /usr/sbin/chown -R "$user":staff "$path_to_item"
}


search_for_enrollment_logs() {
    # Loop through the contents of the directory and check for enrollment-date.logs.
    # Takes in the ENROLLMENT_LOG_DIR
    local dir="$1"
    for entry in $dir/*; do

        # Store just the file name at the end of the path.
        file=$(/usr/bin/basename "$entry")

        if printf "%s" "$file" | /usr/bin/grep -q "enrollment"; then
            # Found some enrollment logs.
            logging "info" "Copying $entry"
            /bin/cp -a "$entry" "$dir"
        fi
    done
}


check_jamf_enrollment_complete() {
    # Look for the EnrollmentComplete status in the jamf.log.
    local log="$1"
    local enrollment_status=false
    if /usr/bin/grep -q "enrollmentComplete" "$log" ; then
        enrollment_status=true
    fi
    # Return enrollment_status
    printf "$enrollment_status\n"
}


check_for_device_signature_errors() {
    # Look for device signature errors and return result.
    # Takes in the path to the jamf.log file.
    local log="$1"
    local err_status=false

    i=1
    while ! /usr/bin/grep -q "Device Signature Error" "$log"; do
        logging "info" "Checking for Device Signature Errors in jamf.log ..."
        /bin/sleep 1
        i=$((i+1))

        if [[ $i -eq 15 ]]; then
            # If i equals 30 then we have been looking for the error in jamf.log for
            # 30 seconds. We should break out of the loop and move on to the next check.
            logging "info" "Waited for 15 seconds ..."
            break
        fi
    done

    if /usr/bin/grep -q "Device Signature Error" "$log"; then
        logging "error" "Found device signature errors in $log"
        err_status=true
    fi
    # Return err_status
    printf "%s\n" "$err_status"
}


remove_framework() {
    # Remove the Jamf MDM framework
    local rem_status=false
    /usr/local/jamf/bin/jamf removeFramework
    local ret="$?"
    if [[ "$ret" -eq 0 ]]; then
        logging "INFO" "Successfully removed the Jamf Framework ..."
        rem_status=true
    fi
    printf "$rem_status\n"
}


return_system_profiles() {
    # Return all profiles set at the computer level based on provided type.
    local type="$1"
    all_profiles=$(/usr/bin/profiles show -type "$type")
    printf "%s" "$all_profiles"
}


return_user_profiles() {
    # Return all installed configuration profiles for a given user.
    local user="$1"
    all_user_profiles=$(/usr/bin/profiles show all -user "$user")
    printf "%s" "$all_user_profiles"
}


return_profile_uuid() {
    # Parse a list of configuration porfiles and return the UUID of the provided
    # profile name.
    local profile_list="$1"
    local profile_name="$2"
    uuid=$(printf "%s" "$profile_list" | \
        /usr/bin/grep -A 5 "attribute: name: $profile_name" | \
        /usr/bin/grep "profileIdentifier" | \
        /usr/bin/awk -F ":" '{print $3}' | \
        /usr/bin/sed -e 's/^[[ \t]]*//')

    local ret="$?"
    if [[ "$ret" -ne 0 ]] || [[ "$uuid" = "" ]]; then
        # Failed to remove the configuration profile.
        logging "error" "Failed to return UUID for profile $profile_name ..."
    else
        # Return the UUID of the profided profile
        printf "%s" "$uuid"
    fi
}


remove_configuration_profile() {
    # Remove a configuration profile given the profileIdentifier.
    local type="$1"
    local user="$2"
    local id="$3"
    local rem_status=false

    "/usr/bin/profiles" remove -type "$type" -user "$user" -identifier "$id"
    ret="$?"
    if [[ "$ret" -eq 0 ]]; then
        logging "info" "Profile ($id) removed Successfully ..."
        rem_status=true
    fi
    printf "%s\n" "$rem_status"
}


renew_enrollment() {
    # Renew the enrollment profile
    local renew_status=false

    "/usr/bin/profiles" renew -type enrollment
    local ret="$?"

    i=1
    while [[ "$ret" -ne 0 ]]; do
        # We were not able to remove the Jamf MDM Profile
        logging "warning" "Renew enrollment command failed ..."
        # logging "ERROR" "Error: $cmd"
        logging "INFO" "Going to try again in 5 seconds ..."
        /bin/sleep 5
        "/usr/bin/profiles" renew -type enrollment
        ret="$?"
        i=$((i+1))

        if [[ "$i" -eq 12 ]]; then
            logging "WARNING" "We have tried renewing the DEP Enrollment profile over the last few seconds without any luck ..."
            logging "WARNING" "Will not try again ..."
            ret="$ret"
            break
        fi
    done

    if [[ "$ret" -eq 0 ]]; then
        #statements
        logging "INFO" "Successfully sent the renew enrollment command ..."
        renew_status=true
    fi

    # Return the enrollment status
    printf "%s\n" "$renew_status"
}


build_notification_window() {
    # Create a notification window letting the user know what they need to do with the
    # information gathered.
    # Display computer information to the user.

    local ip_address="$(return_ip_address)"
    local sn="$(return_serial_number)"
    local computer_name="$(return_computer_name)"

    local cu="$1"
    local sig_err_status="$2"
    local mdm_framework_removal_status="$3"
    local mdm_ca_cert_removal_status="$4"
    local renew_enrollment_status="$5"
    local jamf_log_status="$6"
    local internet_status="$7"
    local jamf_enrollment_complete="$8"

    #
    # Determine which dialog message to show the user.
    #

    if [[ "$internet_status" = false ]]; then
        dialog_message="
        No valid internet connection found. Please ensure that
        the Mac is connected to a valid internet connection
        and that you can reach google.com. Then, try running
        this tool again.

        For additional information please take a look at the
        Enrollment_Logs folder on your Desktop."

    elif [[ "$sig_err_status" = true ]] && [[ "$renew_enrollment_status" = true ]]; then
        dialog_message="
        We found Device Signature errors in the Jamf
        logs. We are now attempting to fix the
        provisioning on this Mac. Please hang tight.

        You should see an authentication request from Jamf.

        Additional log information can be found on
        your Desktop in the Enrollment_Logs folder."

    elif [[ "$jamf_enrollment_complete" = false ]]; then
        dialog_message="
        No action was taken on this Mac ...

        A reason for the Jamf enrollment failure was not able
        to be determined at this time.

        Please reachout to the IT service desk for assistance
        and provide the log files located in the
        Enrollment_Log on your Desktop."

    elif [[ "$jamf_log_status" = false ]] && \
        [[ "$renew_enrollment_status" = true ]]; then
        dialog_message="
        The jamf.log file was not found. This typically means
        that the Jamf enrollment process never started. An
        attempt to reinitiate the enrollment process has begun.
        You should see an authentication request from Jamf.

        Please take a look at the Enrollment_Logs folder on
        your Desktop for additional information and detail to
        see what else may have caused the Jamf device
        enrollment issue."

    else
        dialog_message="
        No action was taken on this Mac ...

        The Jamf enrollment on this Mac appears to
        have completed successfully.

        Please take a look at the Enrollment_Logs folder on
        your Desktop for additional information.

        If you still feel that something is not quite
        right please reachout to the IT service desk and
        provide the logs from the folder mentioned above."
    fi

    #
    # Populate status messages
    #

    # Validate internet status
    if [[ "$internet_status" = true ]]; then
        #statements
        internet_status_message="✅:  Internet connection found"
    else
        internet_status_message="❌:  Internet connection not found"
    fi

    # Validate jamf.log status
    if [[ "$jamf_log_status" = true ]]; then
        #statements
        jamf_log_status_msesage="✅:  jamf.log found"
    else
        jamf_log_status_msesage="❌:  jamf.log not found"
    fi

    # Validate Device Signature Erorrs status
    if [[ "$sig_err_status" = true ]]; then
        #statements
        sig_err_status_message="✅:  Device Signature Errors found in jamf.log"
    else
        sig_err_status_message="❌:  Device Signature Errors not found in jamf.log"
    fi

    # Validate check_jamf_enrollment_complete status
    if [[ "$jamf_enrollment_complete" = true ]]; then
        #statements
        jamf_enrollment_complete_message="✅:  enrollmentComplete found in jamf.log"
    else
        jamf_enrollment_complete_message="❌:  enrollmentComplete not found in jamf.log"
    fi

    # Validate mdm_framework_removal_status status
    if [[ "$mdm_framework_removal_status" = true ]]; then
        #statements
        mdm_framework_removal_status_message="✅:  MDM Profile removed"
    else
        mdm_framework_removal_status_message="❌:  MDM Profile not removed or not present"
    fi

    # Validate mdm_ca_cert_removal_status status
    if [[ "$mdm_ca_cert_removal_status" = true ]]; then
        #statements
        mdm_ca_cert_removal_status_message="✅:  MDM CA Certificate removed"
    else
        mdm_ca_cert_removal_status_message="❌:  MDM CA Certificate not removed or not present"
    fi

    # Validate enrollment status
    if [[ "$renew_enrollment_status" = true ]]; then
        #statements
        renew_enrollment_status_message="✅:  Re-enrollment initiated"
    else
        renew_enrollment_status_message="❌:  Re-enrollment not initiated"
    fi

    #
    # Display dialog box to user.
    #

    if [[ "$internet_status" = false ]]; then
        # Display computer information to the user.
        /usr/bin/osascript -e 'display dialog "
        Mac Information

        IP Address:               '"$ip_address"'
        Serial Number:         '"$sn"'
        Computer Name:     '"$computer_name"'
        Current User:           '"$cu"'

        Enrollment Clean up Status

        '"$internet_status_message"'
        '"$dialog_message"'" with title "Fix Provisioning Report '"$VERSION"'" buttons {"OK"} default button 1'

    elif [[ "$sig_err_status" = true ]]; then
        # Display computer information to the user.
        /usr/bin/osascript -e 'display dialog "
        Mac Information

        IP Address:               '"$ip_address"'
        Serial Number:         '"$sn"'
        Computer Name:     '"$computer_name"'
        Current User:           '"$cu"'

        Enrollment Clean up Status

        '"$internet_status_message"'
        '"$jamf_log_status_msesage"'
        '"$sig_err_status_message"'
        '"$mdm_framework_removal_status_message"'
        '"$mdm_ca_cert_removal_status_message"'
        '"$renew_enrollment_status_message"'
        '"$dialog_message"'" with title "Fix Provisioning Report '"$VERSION"'" buttons {"OK"} default button 1'

    elif [[ "$jamf_enrollment_complete" = false ]]; then
        # Display computer information to the user.
        /usr/bin/osascript -e 'display dialog "
        Mac Information

        IP Address:               '"$ip_address"'
        Serial Number:         '"$sn"'
        Computer Name:     '"$computer_name"'
        Current User:           '"$cu"'

        Enrollment Clean up Status

        '"$internet_status_message"'
        '"$jamf_log_status_msesage"'
        '"$sig_err_status_message"'
        '"$jamf_enrollment_complete_message"'
        '"$dialog_message"'" with title "Fix Provisioning Report '"$VERSION"'" buttons {"OK"} default button 1'

    elif [[ "$jamf_log_status" = false ]] && \
        [[ "$renew_enrollment_status" = true ]]; then
        # Display computer information to the user.
        /usr/bin/osascript -e 'display dialog "
        Mac Information

        IP Address:               '"$ip_address"'
        Serial Number:         '"$sn"'
        Computer Name:     '"$computer_name"'
        Current User:           '"$cu"'

        Enrollment Clean up Status

        '"$internet_status_message"'
        '"$jamf_log_status_msesage"'
        '"$renew_enrollment_status_message"'
        '"$dialog_message"'" with title "Fix Provisioning Report '"$VERSION"'" buttons {"OK"} default button 1'

    else
        # Display computer information to the user.
        /usr/bin/osascript -e 'display dialog "
        Mac Information

        IP Address:               '"$ip_address"'
        Serial Number:         '"$sn"'
        Computer Name:     '"$computer_name"'
        Current User:           '"$cu"'

        Enrollment Clean up Status

        '"$internet_status_message"'
        '"$jamf_log_status_msesage"'
        '"$jamf_enrollment_complete_message"'
        '"$dialog_message"'" with title "Fix Provisioning Report '"$VERSION"'" buttons {"OK"} default button 1'
    fi
}


main

exit "$RET"
