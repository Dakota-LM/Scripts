<#
.SYNOPSIS
    Sends a SyncML request to the local MDM server.

.DESCRIPTION
    Sends a SyncML request to the local MDM server.  This must be run with admin rights in a 64-bit PowerShell process started with the
    "-MTA" switch.
    
.PARAMETER SyncML
    Specifies the explicit SyncML XML string that should be sent to the local MDM service.

.PARAMETER OmaUri
    Specifies the OMA-URI path that should be used to construct a SyncML request.

.PARAMETER Cmd
    Specifies the MDM command that should be used to construct a SyncML request.  Valid values are "Get", "Add", "Atomic", "Delete", "Exec", "Replace", and "Result".  The default is "Get".

.PARAMETER Format
    Specifies the format of the data value to be included in the SyncML request.  The default value is "int".

.PARAMETER Type
    Specifies the type of the data value to be included in the SyncML request.  The default value is "text/plain".

.PARAMETER Data
    Specifies the data to be included in the SyncML request.  This is optional for some requests (e.g. "Get").

.PARAMETER Raw
    Specifies that the result should be returned as a raw string (exactly as returned by the local MDM service) rather than as a PowerShell object.

.EXAMPLE
    Send-LocalMDMRequest -OmaUri "./DevDetail/Ext/Microsoft/ProcessorArchitecture"

.EXAMPLE
    Send-LocalMDMRequest -OmaUri "./DevDetail/Ext/Microsoft/ProcessorArchitecture"

.OUTPUTS
    The result of the SyncML request.  If -Raw is specified, this will be an XML string.  Otherwise, it will be a PowerShell object.

.LINK
    https://oofhours.com/
    https://github.com/ms-iot/iot-core-azure-dm-client/blob/master/src/SystemConfigurator/CSPs/MdmProvision.cpp
    https://docs.microsoft.com/en-us/windows/iot-core/develop-your-app/embeddedmode

#>
[cmdletbinding()]
Param(
    [Parameter(ParameterSetName='Raw', Mandatory = $true)]
    [String]$SyncML,
    [Parameter(ParameterSetName='Assisted', Mandatory = $true)]
    [String]$OmaUri,
    [Parameter(ParameterSetName='Assisted', Mandatory = $false)]
    [ValidateSet("Get", "Add", "Atomic", "Delete", "Exec", "Replace", "Result")]
    [String]$Cmd = "Get",
    [Parameter(ParameterSetName='Assisted', Mandatory = $false)]
    [String]$Format = "int",
    [Parameter(ParameterSetName='Assisted', Mandatory = $false)]
    [String]$Type = "text/plain",
    [Parameter(ParameterSetName='Assisted', Mandatory = $false)]
    [String]$Data = "",
    [Parameter()]
    [Switch]$Raw = $false
)
BEGIN {
    $source = @"
using System;
using System.Runtime.InteropServices;

namespace MDMLocal
{
    public class Interface
    {
        [DllImport("mdmlocalmanagement.dll", CharSet = CharSet.Unicode, SetLastError = true)] 
        internal static extern uint RegisterDeviceWithLocalManagement(out uint alreadyRegistered);

        [DllImport("mdmlocalmanagement.dll", CharSet = CharSet.Unicode, SetLastError = true)] 
        public static extern uint UnregisterDeviceWithLocalManagement();

        [DllImport("mdmlocalmanagement.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        internal static extern uint ApplyLocalManagementSyncML(string syncMLRequest, out IntPtr syncMLResult);

        [DllImport("kernel32.dll")] 
        internal static extern uint LocalFree(IntPtr hMem);

        public static uint Apply(string syncML, out string syncMLResult)
        {
            uint rc;
            uint alreadyRegistered;
            IntPtr resultPtr;

            rc = RegisterDeviceWithLocalManagement(out alreadyRegistered);

            rc = ApplyLocalManagementSyncML(syncML, out resultPtr);
            syncMLResult = "";
            if (resultPtr != null)
            {
                syncMLResult = Marshal.PtrToStringUni(resultPtr);
                LocalFree(resultPtr);
            }
            return rc;
        }
    }
}
"@

    Invoke-ImmyCommand -Context System -ScriptBlock {
        # Add-Type -TypeDefinition $($using:source) -Language CSharp
        # Enable embedded mode
        $uuidBytes = ([GUID](Get-WMIObject -Class win32_computersystemproduct).UUID).ToByteArray()
        $hasher = [System.Security.Cryptography.HashAlgorithm]::Create('sha256')
        $hash = $hasher.ComputeHash($uuidBytes)
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\embeddedmode\Parameters" -Name "Flags" -Value $hash
    }
}
PROCESS {
    Invoke-ImmyCommand -Context System -ScriptBlock {
        Add-Type -TypeDefinition $($using:source) -Language CSharp
        $global:localMDMCmdCounter = 0

        # Depending on the parameter set, build or use SyncML
        if ($PSCmdlet.ParameterSetName -eq "Raw") {
            $useSyncML = $using:SyncML       
        } else {
            $useSyncML = @"
<SyncBody>
    <$($using:Cmd)>
        <CmdID>1</CmdID>
        <Item>
            <Target>
                <LocURI>$($using:OmaUri)</LocURI>
            </Target>
            <Meta>
                <Format xmlns="syncml:metinf">$($using:Format)</Format>
                <Type xmlns="syncml:metinf">$($using:Type)</Type>
            </Meta>
            <Data>$($using:Data)</Data>
        </Item>
    </$($using:Cmd)>
</SyncBody>
"@
        }

        # Make sure we have a unique command ID
        # TODO: updateCmdId needs to be adopted to function within an
        [xml] $xml = $useSyncML
        # Set the incremented CmdID value
        $global:localMDMCmdCounter++
        $xml.SyncBody.FirstChild.CmdID = $global:localMDMCmdCounter.ToString()

        $cmdId, $locURI, $updatedSyncML = $global:localMDMCmdCounter, $xml.SyncBody.FirstChild.Item.Target.LocURI, $xml.OuterXml
        #$cmdId, $locURI, $updatedSyncML = updateCmdId($useSyncML)

        # Make a request and check for fatal errors
        $syncMLResultString = ""
        $rc = [MDMLocal.Interface]::Apply($updatedSyncML, [ref]$syncMLResultString)
        if ($rc -eq 2147549446) {
            throw "MDM local management requires running powershell.exe with -MTA."
        } elseif ($rc -eq 2147746132) {
            throw "MDM local management requires a 64-bit process."
        } elseif ($syncMLResultString -like "Error*") {
            throw $syncMLResultString
        } elseif ($rc -ne 0) {
            throw "Unexpected return code from MDM local management: $rc"
        }

        # Return the response details (Status of 200 is success)
        if ($($using:Raw)) {
            $syncMLResultString
        } else {
            [xml] $syncMLResult = $syncMLResultString
            $status = $syncMLResult.SyncML.SyncBody.Status[1]
            New-Object PSObject -Property ([ordered] @{
                CmdId = $cmdId
                Cmd = $status.Cmd
                Status = $status.Data
                OmaUri = $locURI
                Data = $syncMLResult.SyncML.SyncBody.Results.Item.Data
            })
        }
    }
}