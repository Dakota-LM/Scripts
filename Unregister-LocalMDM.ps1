<#
.SYNOPSIS
    Unregisters the local MDM server.

.DESCRIPTION
    Unregisters the local MDM server.  This will in some cases revert any policies configured via the local MDM server back to their default values.

.EXAMPLE
    Unregister-LocalMDM

.OUTPUTS
    A message confirming the unregister operation.

#>
[cmdletbinding()]
Param(
)
PROCESS {
    Invoke-ImmyCommand -Context System -ScriptBlock {
        $rc = [MDMLocal.Interface]::UnregisterDeviceWithLocalManagement()
        Write-Host "Unregisterd, rc = $rc"
    }
}