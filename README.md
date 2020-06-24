# Fix Provisioning Tool

**NOTE**: This repo is a proof of concept and is still in early stages of development. Most of the common use cases have been tested, but use with caution ...


## About this Repo

fix-provisioning-tool is a package containing a script that will help remediate automated enrollment issues due to ABM communication failures or glitches during the Apple Setup Assistant process. The main error that this tool looks for is `Device Signature Error`.

### This tool performs the following actions

- Checks to see if files like `jamf.log`, the jamf binary, and other Jamf related collateral are present on a Mac.
- Check for the "Device Signature Error" string in the `jamf.log`.
- If `Device Signature Error` string is not found the tool will check for `enrollmentComplete` in the `jamf.log`.
- If needed, attempts to remove the Jamf MDM Profile, Jamf Framework, Jamf CA Certificate profile.
- If needed, attempts to renew the device enrollment profile on the Mac and initiate automated enrollment again.
- Displays a report of findings and information to direct the user/technician in the direction of a potential cause and path to resolution.
- Generates an `Enrollment_Logs` directory on the user's Desktop containing a copy of the `jamf.log`, and copies of enrollment logs in `/Library/Logs`, and a copy of the fix\_provisioning\_tool.log.


## How to Run the Tool

1. Download the latest package release from [here](https://github.com/icwfrepo/fix-provisioning-tool/releases/tag/latest).

2. Install the package and enter admin credentials.

    - You can run the package from anywhere but the best place is the Desktop.

3. The tool will take a few minutes to complete.
4. Take a look a the report and `Enrollment_Logs` directory on the Desktop.

    <img src="screenshots/fpt_example.gif" alt="Example of FPT running" width="612"/>


## Example Reports

### jamf.log not found

<img src="screenshots/fpt_not_jamf_log_found.png" alt="device signature errors found" width="350"/>


### Device Signature Errors Found ...

<img src="screenshots/fpt_device_sig_error_found.png" alt="No jamf.log found" width="350"/>


## What this tool does not do ...

- It (this tool) will not catch or handle other enrollment scenarios such as loss of network connectivity during initial automated enrollment.
- It will not catch or handle errors related to downloading packages or policies from Jamf during the automated enrollment process.
- It will not attempt to reinstall software or kick off policies scoped to the Mac.
- It is not intended to be used as a remediation for failures stemming from User Initiated Enrollment. Although it will suggest if it thinks that UIE may have been used to enroll the Mac due to the `profiles renew -type enrollment` command failing to renew the device enrollment profile.

## Change Log: [Here](https://github.com/icwfrepo/fix-provisioning-tool/blob/master/CHANGELOG.md)


## ToDo

- ✅ - v0.0.2 - Add the ability to remove the MDM certificate payload from profiles.
- ✅ - v0.0.3 - Add a UI notification at the end to let the user know what they need to do with the information gathered from the tool.
- ✅ - v2.0.0 - Add ability to retry an enrollment if nothing Jamf related is found. I.E. the provisioning never started.
- ✅ - v2.0.0 - Additional enrollment error checking and handling.
- ✅ - v2.0.0 - Notarize ...
- 🔲 - Figure out how to turn this into an app.
- 🔲 - Convert to python or swift or golang ... maybe 😜.
