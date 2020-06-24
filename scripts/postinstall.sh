#!/usr/bin/env sh

# GitHub: @captam3rica


#
#   A post-install script to launch fix-provisioning-tool
#


RESULT=0

# Define the current working directory
HERE=$(/usr/bin/dirname "$0")
SCRIPT_NAME="fix_provisioning_tool.sh"
SCRIPT_PATH="$HERE/$SCRIPT_NAME"

main() {
    /usr/bin/logger "Setting permissions on the script ..."
    /bin/chmod 755 "$SCRIPT_PATH"
    /usr/bin/logger "Launching the script ..."
    /bin/zsh "$SCRIPT_PATH"
}

# Call main
main

exit "$RESULT"
