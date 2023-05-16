$TestResult = Send-LocalMDMRequest -OMAURI $OMAURI -Cmd Get

switch($method){ 
    test{
        Write-Host -Fore DarkGreen $TestResult

        Write-Host "$($TestResult.Data) and $DataValue"
        if ($null -eq $TestResult.Data -or $TestResult.Data -ne $DataValue -and $TestResult.Status -eq "200"){
            return $false
        }else{
            return $true
        }

    }
    get{
        return $TestResult.Data
    }
    set{
        if ($Unregister){
            Unregister-LocalMDM
            return
        }
        if ($null -ne $DataValue -and $SetCmd -eq "Add"){
            $SetCmd = "Replace"
        }
        Send-LocalMDMRequest -OMAURI $OMAURI -Cmd $SetCmd -Data $DataValue
    }
}