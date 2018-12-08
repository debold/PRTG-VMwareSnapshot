# PRTG-VMwareSnapshot
You can use this script to monitor VMs in your vCenter having open snapshots for a long time.

You need to have VMware PowerCLI installed on your PRTG probe in order for the script to work.

Use the documentation within the script to find the correct parameters.

Example:
    Get-VmwareSnapshots.ps1 -ViServer %host -User %linuxuser -Password %linuxpassword

Uses Linux username and password from parent device in PRTG.
