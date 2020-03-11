#!/bin/sh

# GitHub: @captam3rica
VERSION=0.0.6

#
#   A script to help workaround automated enrollment issues due to DEP communication
#   failure or glitches.
#

# Set exit code to 0 initially
RET=0

# Incase we need to know where the current directory is
HERE=$(/usr/bin/dirname "$0")

# Constants
SCRIPT_NAME=$(/usr/bin/basename "$0" | /usr/bin/awk -F "." '{print $1}')
ROOT_LIB="/Library"
JAMF_LOG="/var/log/jamf.log"
TODAY=$(date +"%Y-%m-%d")
ENROLLMENT_LOG_DIR="$ROOT_LIB/Logs"
ENROLLMENT_COMPLETE_STUB="/Users/Shared/EnrollmentComplete.txt"

# Binaries
IFCONFIG="/sbin/ifconfig"
JAMF="/usr/local/jamf/bin/jamf"
NETWORKSETUP="/usr/sbin/networksetup"
OSASCRIPT="/usr/bin/osascript"
PROFILES="/usr/bin/profiles"
SCUTIL="/usr/sbin/scutil"
SYSTEM_PROFILER="/usr/sbin/system_profiler"


# Log stuff
LOG_NAME="fix_provisioning_tool.log"
LOG_PATH="$ROOT_LIB/Logs/$LOG_NAME"


logging() {
    # Pe-pend text and print to standard output
    # Takes in a log level and log string.
    # Example: logging "INFO" "Something describing what happened."

    log_level=$(printf "$1" | /usr/bin/tr '[:lower:]' '[:upper:]')
    log_statement="$2"
    LOG_NAME="fix_provisioning_tool.log"
    LOG_PATH="$ROOT_LIB/Logs/$LOG_NAME"

    if [ -z "$log_level" ]; then
        # If the first builtin is an empty string set it to log level INFO
        log_level="INFO"
    fi

    if [ -z "$log_statement" ]; then
        # The statement was piped to the log function from another command.
        log_statement=""
    fi

    DATE=$(date +"[%b %d, %Y %Z %T $log_level]:")
    printf "%s %s\n" "$DATE" "$log_statement" >> "$LOG_PATH"
}


get_current_user() {
    # Return the current user
    printf '%s' "show State:/Users/ConsoleUser" | \
        /usr/sbin/scutil | \
        /usr/bin/awk '/Name :/ && ! /loginwindow/ {print $3}'
}


copy_files() {
    # Move files from one place to another
    # takes in source destination
    /bin/cp -a "$1" "$2"
}


all_network_devices () {
    # Return an array of all network device interfaces
    # Get network device interfaces
    "$NETWORKSETUP" -listallhardwareports | \
            /usr/bin/grep "Device" | \
            /usr/bin/awk -F ":" '{print $2}' | \
            /usr/bin/sed -e 's/^[ \t]*//'
}


active_network_devices () {
    # Find the active network interfaces

    # Initialize counter
    COUNT=0
    DEVICE_LIST="$(all_network_devices)"
    for device in $DEVICE_LIST; do
        # Loop through network hardware devices
        # Get the hardware port for a given network device
        HARDWARE_PORT=$("$NETWORKSETUP" -listallhardwareports | \
            /usr/bin/grep -B 1 "$device" | \
            /usr/bin/grep "Hardware Port" | \
            /usr/bin/awk -F ":" '{ print $2 }' | \
            sed -e 's/^[ \t]*//')

        # See if given device has an active connection
        # Return 0 for active or 1 for inactive
        "$IFCONFIG" "$device" 2>/dev/null | \
            /usr/bin/grep "status: active" > /dev/null 2>&1

        # Outcome of previous command
        RESPONSE="$?"

        # Increment the counter
        COUNT=$((COUNT+1))

        if [ "$RESPONSE" -eq 0 ]; then
            # If network device is active
            printf "%s\n" "$HARDWARE_PORT"
            break
        fi
    done
}


return_ip_address () {
    # Return the IP Address assigned to a given Hardware Interface

    # Return the Hardware Port of the active interface.
    hwp="$(active_network_devices)"

    "$NETWORKSETUP" -getinfo "$hwp" | \
        /usr/bin/grep "^IP address:" | \
        /usr/bin/awk -F ":" '{print $2}' | \
        /usr/bin/sed -e 's/^[ \t]*//'
}


return_serial_number () {
    # Get the device serial number
    "$SYSTEM_PROFILER" SPHardwareDataType | \
        /usr/bin/awk '/Serial\ Number\ \(system\)/ {print $NF}'
}


return_computer_name () {
    # Get the computer name
    "$SCUTIL" --get ComputerName
}


create_directory(){
    # Create a directory at the provided path.
    path_input="$1"
    if [ ! -d "$path_input" ]; then
        # Determine if the path_input does not exist. If it doesn't, create it.
        /bin/mkdir -p "$path_input"
    else
        # Log that the path_input already exists.
        logging "" "$path_input already exists."
    fi
}


set_ownership() {
    # Set ownership for folder of directory
    # Parameters
    #   $1: user
    #   $2: folder or directory - must be full path
    #
    user="$1"
    path_to_item="$2"
    /usr/sbin/chown -R "$user":staff "$path_to_item"
}


search_for_enrollment_logs() {
    # Loop through the contents of the directory and check for enrollment-date.logs.
    # Takes in the ENROLLMENT_LOG_DIR
    dir="$1"
    for entry in $dir/*; do

        # Store just the file name at the end of the path.
        file=$(/usr/bin/basename "$entry")

        if printf "%s" "$file" | /usr/bin/grep -q "enrollment"; then
            # Found some enrollment logs.
            logging "info" "Copying $entry"
            copy_files "$entry" "$enrollment_log_dir"
        fi
    done
}


search_for_enrollment_stub() {
    # Check for the present of the enrollment complete stub file.
    # Takes in the ENROLLMENT_COMPLETE_STUB as a parameter
    file="$1"
    if [ -f "$file" ]; then
        # The existance of this file means that the device was able to make it all the
        # way through the provisioning process, but perhaps something else cause an
        # issue with part of the process.
        logging "info" "$file was found ..."
        logging "info" "There is a good chance that a DEVICE SIGNATURE ERROR was not the reason for this enrollment failing."
    else
        logging "info" "$file not found ..."
    fi
}


check_jamf_enrollment_status() {
    # Look for the EnrollmentComplete status in the jamf.log.
    log="$1"
    if /usr/bin/grep -q "enrollmentComplete" "$log" ; then
        JAMF_ENROLLMENT_COMPLETE=true
        printf "%s" "$JAMF_ENROLLMENT_COMPLETE"
    else
        JAMF_ENROLLMENT_COMPLETE=false
        printf "%s" "$JAMF_ENROLLMENT_COMPLETE"
    fi
}


check_for_device_signature_errors() {
    # Look for device signature errors and return result.
    # Takes in the path to the jamf.log file.
    log="$1"

    i=1
    logging "info" "Checking for device signature errors ..."
    while ! /usr/bin/grep -q "Device Signature Error" "$log"; do
        logging "info" "Checking for Device Signature Errors in jamf.log ..."
        /bin/sleep 1
        i=$((i+1))

        if [ $i -eq 15 ]; then
            # If i equals 30 then we have been looking for the error in jamf.log for
            # 30 seconds. We should break out of the loop and move on to the next check.
            logging "info" "Waited for 15 seconds ..."
            logging "info" "No device signature errors found in jamf.log ..."
            logging "info" "Moving on ..."
            FOUND_DEVICE_SIG_ERR_STATUS=false
            printf "%s\n" "$FOUND_DEVICE_SIG_ERR_STATUS"
            break
        fi
    done

    if /usr/bin/grep -q "Device Signature Error" "$log"; then
        logging "error" "Found device signature errors in $log"
        FOUND_DEVICE_SIG_ERR_STATUS=true
        printf "%s\n" "$FOUND_DEVICE_SIG_ERR_STATUS"
    fi
}


remove_mdm_profile() {
    # Remove the Jamf MDM Profile
    logging "INFO" "Attempting to remove the Jamf MDM Profile ..."
    "$JAMF" removeMdmProfile
    RET="$?"
    if [ "$RET" -ne 0 ]; then
        # We were not able to remove the Jamf MDM Profile
        logging "ERROR" "Unable to remove the MDM Profile from this computer ..."
        logging "ERROR" "Error: $RET: No such file or directory"
        RET="$RET"
        JAMF_PROFILE_REMOVAL_STATUS=false
        printf "$JAMF_PROFILE_REMOVAL_STATUS\n"
    else
        logging "INFO" "Successfully removed the MDM Profile ..."
        JAMF_PROFILE_REMOVAL_STATUS=true
        printf "$JAMF_PROFILE_REMOVAL_STATUS\n"
    fi
}


remove_framework() {
    # Remove the Jamf MDM framework
    logging "INFO" "Attempting to remove the Jamf Framework ..."
    "$JAMF" removeFramework
    RET="$?"
    if [ "$RET" -ne 0 ]; then
        # We were not able to remove the Jamf MDM Profile
        logging "ERROR" "Unable to remove the Jamf Framework from this computer ..."
        logging "ERROR" "Error: $RET: No such file or directory"
        RET="$RET"
        JAMF_FRAMEWORK_REMOVAL_STATUS=false
        PRINTF "$JAMF_FRAMEWORK_REMOVAL_STATUS\n"
    else
        logging "INFO" "Successfully removed the Jamf Framework ..."
        JAMF_FRAMEWORK_REMOVAL_STATUS=true
        PRINTF "$JAMF_FRAMEWORK_REMOVAL_STATUS\n"
    fi
}


return_system_profiles() {
    # Return all profiles set at the computer level based on provided type.
    type="$1"
    all_profiles=$($PROFILES show -type "$type")
    printf "%s" "$all_profiles"
}


return_user_profiles() {
    # Return all installed configuration profiles for a given user.
    user="$1"
    all_user_profiles=$(/usr/bin/profiles show all -user "$user")
    printf "%s" "$all_user_profiles"
}


return_profile_uuid() {
    # Parse a list of configuration porfiles and return the UUID of the provided
    # profile name.
    profile_list="$1"
    profile_name="$2"
    uuid=$(printf "%s" "$profile_list" | \
        /usr/bin/grep -A 5 "attribute: name: $profile_name" | \
        /usr/bin/grep "profileIdentifier" | \
        /usr/bin/awk -F ":" '{print $3}' | \
        /usr/bin/sed -e 's/^[ \t]*//')

    ret="$?"
    if [ "$ret" -ne 0 ] || [ "$uuid" = "" ]; then
        # Failed to remove the configuration profile.
        logging "error" "Failed to return UUID for profile $profile_name ..."
    else
        # Return the UUID of the profided profile
        printf "%s" "$uuid"
    fi
}


remove_configuration_profile() {
    # Remove a configuration profile given the profileIdentifier.
    type="$1"
    user="$2"
    id="$3"

    "$PROFILES" remove -type "$type" -user "$user" -identifier "$id"
    ret="$?"
    if [ "$ret" -ne 0 ]; then
        # Failed to remove the configuration profile.
        logging "error" "Failed to remove configuration profile ..."
        PROFILE_REMOVAL_STATUS=false
        printf "%s\n" "$PROFILE_REMOVAL_STATUS"
    else
        logging "info" "Profile ($id) removed Successfully ..."
        PROFILE_REMOVAL_STATUS=true
        printf "%s\n" "$PROFILE_REMOVAL_STATUS"
    fi
}


check_the_internet_connection() {
    # Check the internet connection to make sure we can get out.
    /sbin/ping -q -c 1 -W 1 8.8.8.8 >/dev/null
    RET="$?"

    i=1
    while [ "$RET" -ne 0 ]; do
        # We are waiting for a valid internet connection
        logging "info" "Waiting for a valid internet connection ..."
        /bin/sleep 1
        /sbin/ping 8.8.8.8
        RET="$?"

        i=$((i=1))
        if [ "$i" -eq 12 ]; then
            logging "warning" "We could not establish a valid internet connection ..."
            INTERNET_STATUS=false
            printf "%s\n" "$INTERNET_STATUS"
            break
        fi
    done

    if [ "$RET" -eq 0 ]; then
        logging "info" "Found a valid internet connection ..."
        INTERNET_STATUS=true
        printf "%s\n" "$INTERNET_STATUS"
    fi
}


renew_enrollment() {
    # Renew the enrollment profile
    "$PROFILES" renew -type enrollment
    RET="$?"

    i=1
    while [ "$RET" -ne 0 ]; do
        # We were not able to remove the Jamf MDM Profile
        logging "ERROR" "Unable to re-enroll this computer ..."
        # logging "ERROR" "Error: $cmd"
        logging "INFO" "Going to try again in 5 seconds ..."
        /bin/sleep 5
        "$PROFILES" renew -type enrollment
        RET="$?"
        i=$((i+1))

        if [ "$i" -eq 12 ]; then
            logging "WARNING" "We have tried renewing the DEP Enrollment profile over the last few seconds without any luck ..."
            logging "WARNING" "Exiting now."
            RET="$RET"
            RENEW_ENROLLMENT_STATUS=false
            printf "%s\n" "$RENEW_ENROLLMENT_STATUS"
            break
        fi
    done

    if [ "$RET" -eq 0 ]; then
        #statements
        logging "INFO" "Successfully re-enrolled this computer ..."
        RENEW_ENROLLMENT_STATUS=true
        printf "%s\n" "$RENEW_ENROLLMENT_STATUS"
    fi
}


validate_notification_input() {
    # Validate mdm_profile_removal_status status
    # Takes in a boolean as input
    input="$1"
    if [ "$input" = true ]; then
        #statements
        input="✅"
    else
        input="❌"
    fi
}


build_notification_window() {
    # Create a notification window letting the user know what they need to do with the
    # information gathered.
    # Display computer information to the user.

    ip_address="$(return_ip_address)"
    sn="$(return_serial_number)"
    computer_name="$(return_computer_name)"
    jec="$(check_jamf_enrollment_status "$JAMF_LOG")"

    cu="$1"
    sig_err_status="$2"
    mdm_framework_removal_status="$3"
    mdm_ca_cert_removal_status="$4"
    renew_enrollment_status="$5"


    # Validate sig error status
    if [ "$renew_enrollment_status" = false ]; then
        sig_err_status="
        We could not renew the enrollment profile.
        Is it possible that this Mac was enrolled via
        User Initiated Enrollment?
        Additional log information can be found on
        your Desktop in the Enrollment_Logs folder."

    elif [ "$sig_err_status" = true ]; then
        sig_err_status="
        We found Device Signature errors in the Jamf
        logs. We are now attempting to fix the
        provisioning on this Mac. Please hang tight.
        Additional log information can be found on
        your Desktop in the Enrollment_Logs folder."

    elif [ "$jec" = true ]; then
        sig_err_status="
        The Jamf enrollment on this Mac appears to
        have completed successfully. Additional log
        information can be found on your Desktop in
        the Enrollment_Logs folder.
        If you still feel that something is not quite
        right please reachout to the IT service desk."

    else
        sig_err_status="
        No action was taken on this Mac because we
        didn't find any Device Signature errors or
        Enrollment Complete status the Jamf log.
        Please take a look at the Enrollment_Logs folder
        for additional information and detail to see
        what else may have caused the Jamf device
        enrollment issue."
    fi

    # Validate check_jamf_enrollment_status status
    if [ "$jec" = true ]; then
        #statements
        jec="✅"
    else
        jec="❌"
    fi

    # Validate mdm_framework_removal_status status
    if [ "$mdm_framework_removal_status" = true ]; then
        #statements
        mdm_framework_removal_status="✅"
    else
        mdm_framework_removal_status="❌"
    fi

    # Validate mdm_ca_cert_removal_status status
    if [ "$mdm_ca_cert_removal_status" = true ]; then
        #statements
        mdm_ca_cert_removal_status="✅"
    else
        mdm_ca_cert_removal_status="❌"
    fi

    # Validate enrollment status
    if [ "$renew_enrollment_status" = true ]; then
        #statements
        renew_enrollment_status="✅"
    else
        renew_enrollment_status="❌"
    fi

    # Display computer information to the user.
    "$OSASCRIPT" -e 'display dialog "
    Mac Information

    IP Address:               '"$ip_address"'
    Serial Number:         '"$sn"'
    Computer Name:     '"$computer_name"'
    Current User:           '"$cu"'

    Jamf Enrollment Status

    '"$jec"':  Jamf Enrollment Complete

    Enrollment Clean up Status

    '"$mdm_framework_removal_status"':  Removed MDM Profile
    '"$mdm_framework_removal_status"':  Removed MDM FrameWork
    '"$mdm_ca_cert_removal_status"':  Removed MDM CA Certificate
    '"$renew_enrollment_status"':  Re-enrollment Status

    '"$sig_err_status"'" with title "fixprovisioning Report '"$VERSION"'" buttons {"OK"} default button 1'
}


main() {
    # Run the core logic

    logging "info" ""
    logging "info" "Starting $LOG_NAME log"
    logging "info" ""
    logging "info" "Script version: $VERSION"
    logging "info" "Date: $TODAY"
    logging "info" ""

    current_user="$(get_current_user)"
    logging "info" "Current logged in user: $current_user"

    # Make the Enrollment_Log directory where we will store enrollment error logs.
    logging "info" "Creating the Enrollment_Info directory on the user's Desktop"
    enrollment_log_dir="/Users/$current_user/Desktop/Enrollment_Logs"
    create_directory "$enrollment_log_dir"

    logging "info" "Changing ownership to $current_user ..."
    set_ownership "$current_user" "$enrollment_log_dir"

    logging "info" "Looking for $JAMF_LOG"
    # Look to see if the jamf log is present before we go any further.
    if [ ! -f "$JAMF_LOG" ]; then
        logging "error" "The Jamf log is not present on this Mac"
        logging "error" "No reason to continue ..."
        logging "info" "Copying $LOG_NAME to $enrollment_log_dir"
        copy_files "$LOG_PATH" "$enrollment_log_dir"
        exit 0
    else
        logging "info" "Copying "$file
        copy_files "$JAMF_LOG" "$enrollment_log_dir"
    fi

    logging "info" "Searching for enrollment logs in $ENROLLMENT_LOG_DIR"
    search_for_enrollment_logs "$ENROLLMENT_LOG_DIR"

    logging "info" "Checking to see if EnrollmentComplete stub is present ..."
    search_for_enrollment_stub "$ENROLLMENT_COMPLETE_STUB"

    # Checking for bad apples
    signature_error_status="$(check_for_device_signature_errors "$JAMF_LOG")"
    logging "info" "Device Signature Error Status: $signature_error_status"

    if [ "$signature_error_status" = true ]; then
        # We have a bad apple
        system_profiles_list="$(return_system_profiles "configuration")"
        mdm_profile_uuid="$(return_profile_uuid "$system_profiles_list" "MDM Profile")"
        logging "info" "MDM Profile UUID: $mdm_profile_uuid"

        JAMF_FRAMEWORK_REMOVAL_STATUS="$(remove_framework)"

        /bin/sleep 3

        # Make sure that the MDM Profile is gone before moving on.
        while [ -n "$mdm_profile_uuid" ]; do
            # While the MDM Profile is still present loop.
            logging "info" "The MDM Profile ($mdm_profile_uuid) is still present on the Mac ..."
            logging "info" "Waiting for it to be removed before continuing ..."
            /bin/sleep 1

            # Pull the profiles list again
            system_profiles_list="$(return_system_profiles "configuration")"
            mdm_profile_uuid="$(return_profile_uuid "$system_profiles_list" "MDM Profile")"
        done

        logging "info" "Attempting to remove the user CA Certificate profile ..."
        user_profiles_list="$(return_user_profiles "$current_user")"
        builtin_ca_uuid="$(return_profile_uuid "$user_profiles_list" "CA Certificate")"
        logging "info" "CA Cert profile UUID: $builtin_ca_uuid"
        mdm_ca_cert_removal_status="$(remove_configuration_profile "configuration" "$current_user" "$builtin_ca_uuid")"

        # Let things setting a bit.
        /bin/sleep 5

        logging "info" "Checking for a valid internet connection ..."
        INTERNET_STATUS="$(check_the_internet_connection)"

        if [ "$INTERNET_STATUS" = true ]; then
            logging "INFO" "Attempting to re-enroll this computer"
            TRY_ENROLLMENT="$(renew_enrollment)"
        else
            logging "warning" "We could not obtain a valid internet connection."
        fi

    fi

    logging "info" ""
    logging "info" "Ending $LOG_NAME log"
    logging "info" ""

    # Copy the unenrollmentworkaround.log
    logging "info" "Copying the $LOG_PATH ..."
    copy_files "$LOG_PATH" "$enrollment_log_dir"

    # cleanup
    /bin/rm -rf "$LOG_PATH"

    build_notification_window "$current_user" "$signature_error_status" "$JAMF_FRAMEWORK_REMOVAL_STATUS" "$PROFILE_REMOVAL_STATUS" "$TRY_ENROLLMENT"
}

main

exit "$RET"
