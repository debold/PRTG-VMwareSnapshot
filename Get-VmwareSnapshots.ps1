<#
    .SYNOPSIS
    Checks for open VMware snapshots

    .DESCRIPTION
    This scripts uses VMware PowerCLI to connect to the vCenter and discover old snapshots.

    .PARAMETER ViServer 
    *REQUIRED* DNS name or IP address of the vCenter Server. Use %host in PRTG

    .PARAMETER User
    *REQUIRED* Username for login to vCenter. Use UPN (user@domain.com) for Windows authentication. In PRTG there is no placeholder
    for VMware credentials, so use Windows credentials (if UPN is used there) %windowsuser, or tye the credentials into Linux credentials
    in PRTG and use %linuxuser.

    .PARAMETER Password
    *REQUIRED* Password for login to vCenter. If you use Windows credentials in PRTG, type %windowspassword. Else use the Linux credentials
    and type %linuxpassword.

    .PARAMETER WarningHours
    (Optional) Defines the age of a snapshot in hours, when it should alert as WARNING in PRTG.
    Default: 24

    .PARAMETER ErrorHours
    (Optional) Defines the age of a snapshot in hours, when it should alert as ERROR in PRTG.
    Default: 48

    .EXAMPLE
    Sample call from PRTG (EXE/Advanced sensor)
    Get-VmwareSnapshots.ps1 -ViServer %host -User %linuxuser -Password %linuxpassword

    .NOTES
    The VMware PowerCLI must be installed on the PRTG probe for this script to work.

    Author:  Marc Debold
    Version: 1.1
    Version History:
        1.1  08.12.2018  Minor code improvements
        1.0  26.11.2018  Initial release
#>
[CmdletBinding()] param(
    [Parameter()] $ViServer = $null,
    [Parameter()] $User = $null,
    [Parameter()] $Password = $null,
    [Parameter()] $WarningHours = 24,
    [Parameter()] $ErrorHours = 48
)

$WarningVms = @()
$ErrorVms = @()

$ViModule = "VMware.VimAutomation.Core"

# Function to return json formatted error message to PRTG
function Raise-PrtgError {
    [CmdletBinding()] param(
        [Parameter(Mandatory = $true)] $Message
    )
    @{
        "prtg" = @{
            "error" = 1;
            "text" = $Message
        }
    } | ConvertTo-Json
    Exit
}

# Check required parameters
if ($null -eq $ViServer -or $null -eq $User -or $null -eq $Password) {
    Raise-PrtgError -Message "You MUST provide at least ViServer, User and Password as parameters"
}

# Check if PowerCLI modules are in PS path
if (-not (($env:PSModulePath -split ";") -contains "$(${env:ProgramFiles(x86)})\VMware\Infrastructure\PowerCLI\Modules")) {
    $env:PSModulePath += ";$(${env:ProgramFiles(x86)})\VMware\Infrastructure\PowerCLI\Modules"
}

# Load core PowerCLI module
try {
    Import-Module $ViModule -ErrorAction Stop
} catch {
    Raise-PrtgError -Message "Could not load PowerCLI module $ViModule."
}

# Ignore certificate warnings
Set-PowerCLIConfiguration -InvalidCertificateAction ignore -confirm:$false | Out-Null

# Connect to vCenter
try {
    Connect-VIServer -Server $ViServer -User $User -Password $Password -ErrorAction Stop | Out-Null
} catch {
    Raise-PrtgError -Message "Could not connect to vCenter server $ViServer. Error: $($_.Exception.Message)"
}

# Get a list of all VMs
try {
    $VMs = Get-VM -ErrorAction Stop
} catch {
    Raise-PrtgError -Message "Could not get VMs from vCenter $ViServer. Error: $($_.Exception.Message)"
}

# Check snapshots for each VM, skip replication snapshots and snapshots below warning age
foreach ($VM in $VMs) {
    $Snaps = Get-Snapshot -VM $VM -ErrorAction SilentlyContinue | Where-Object { $_.VM -notlike "*_rep" -and $_.Created -lt (Get-Date).AddHours(-1*$WarningHours) }
    if ($null -ne $Snaps) {
        # Save VM names for later use
        if ($Snaps.Created -lt (Get-Date).AddHours(-1*$ErrorHours)) {
            $ErrorVms += $VM.Name
        } else {
            $WarningVms += $VM.Name
        }
    }
}

# Disconnect from vCenter
Disconnect-VIServer -Server $ViServer -Confirm:$false

# JSON output has a bug that 0.5 limit is ignored in sensor creation. XML used instead
<#
@{
    "prtg" = @{
        "result" = @(
            @{
                "channel" = "Snapshots older than ERROR level";
                "value" = $ErrorVms.Count;
                "unit" = "Count";
                "limitmode" = 1;
                "limitmaxerror" = 0.5;
                "limiterrormsg" = "Snapshots older that $($ErrorHours) hour(s): $($ErrorVms -join ', ')"
            };
            @{
                "channel" = "Snapshots older than WARNING level";
                "value" = $WarningVms.Count;
                "unit" = "Count";
                "limitmode" = 1;
                "limitmaxwarning" = 0.5;
                "limitwarningmsg" = "Snapshots older that $($WarningHours) hour(s): $($WarningVms -join ', ')"
            };
)
    }
} | ConvertTo-Json -Depth 3
#>

# Output the sensor information
Write-Host "<prtg>
    <result>
        <channel>Snapshots older than ERROR level</channel>
        <value>$($ErrorVms.Count)</value>
        <unit>Count</unit>
        <limitmode>1</limitmode>
        <limitmaxerror>0.5</limitmaxerror>
        <limiterrormsg>Snapshots older that $($ErrorHours) hour(s): $($ErrorVms -join ', ')</limiterrormsg>
    </result>
    <result>
        <channel>Snapshots older than WARNING level</channel>
        <value>$($WarningVms.Count)</value>
        <unit>Count</unit>
        <limitmode>1</limitmode>
        <limitmaxwarning>0.5</limitmaxwarning>
        <limitwarningmsg>Snapshots older that $($WarningHours) hour(s): $($WarningVms -join ', ')</limitwarningmsg>
    </result>
</prtg>"