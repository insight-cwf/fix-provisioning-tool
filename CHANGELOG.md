# Change Log - Fix Provisioning Tool
All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to Year Notation Versioning.


## Types of Changes

- `Added` for new features.
- `Changed` for changes in existing functionality.
- `Deprecated` for soon-to-be removed features.
- `Removed` for now removed features.
- `Fixed` for any bug fixes.
- `Security` in case of vulnerabilities.


## [v2.0.0] - 2020-06-11

Major over hall of code logic.

- **Added** - Additional report outputs depending on the state of the Mac.
- **Added** - Logic to check for valid internet connection before attempting to do anything else.
- **Added** - Additional logic around checking for the presence of the `jamf.log`
- **Added** - Logic to check for `enrollmentComplete` in the `jamf.log` only if the `Device Signature errors` message is not found.
- **Added** - If neither of the above errors are found a message stating that something else must have caused the enrollment failure.
- **Added** - Ability to attempt an MDM enrollment if the `jamf.log` is not found and no other profiles exist on the machine.


## [v1.0.1] - 2020-05-01

- **Added** - Added a check that will cause the tool to quit if the `enrollment_complete.txt` stub file is found.

## [v0.0.6] - 2020-03-11

- v0.0.6 - Updated log file name.
- v0.0.5 - Added check for valid internet connection before attempting to renew the device enrollment profile.
- v0.0.4
    - Added check and cross emoji to the UI.
    - Added device info to the UI report.
- v0.0.3 - Add a UI notification at the end to let the user know what they need to do with the information gathered from the tool.
- v0.0.2 - Added the ability to remove the MDM certificate payload from profiles.
- v0.0.1 - Initial beta release.





