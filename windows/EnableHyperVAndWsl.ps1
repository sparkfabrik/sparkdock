function Enable-Hyper-V {
    Write-Information -MessageData "----------------------------------Enable Hyper V----------------------------------" -InformationAction Continue
    if ((Get-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V-All -Online).State -ne 'Enabled') {
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All -NoRestart
        return 
    }
    Write-Information -MessageData "----------------------------------HyperV is already enabled----------------------------------" -InformationAction Continue
}

function Enable-Wsl {
    Write-Information -MessageData "----------------------------------Enable Wsl----------------------------------" -InformationAction Continue
    if ((Get-WindowsOptionalFeature -FeatureName Microsoft-Windows-Subsystem-Linux -Online).State -ne 'Enabled') {
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart
    } else {
        Write-Information -MessageData "----------------------------------Microsoft-Windows-Subsystem-Linux is already enabled----------------------------------" -InformationAction Continue
    }
    if ((Get-WindowsOptionalFeature -FeatureName VirtualMachinePlatform -Online).State -ne 'Enabled') {
        Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart
    } else {
        Write-Information -MessageData "----------------------------------VirtualMachinePlatform is already enabled----------------------------------" -InformationAction Continue
    }
}

function Install-Choco {
    Write-Information -MessageData "----------------------------------Install Chocolatey----------------------------------" -InformationAction Continue
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force; 
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; 
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
    } catch {
        Write-Error "Error during the installation of Chocolately error: $_"
    }
}

$osBuildNumber = (Get-CimInstance Win32_OperatingSystem).BuildNumber
$os = (Get-CimInstance Win32_OperatingSystem).Caption
if (($osBuildNumber -ge 19041) -and (($os -like '*Pro*') -or ($os -like '*Enterprise*'))) {
    try {
        Install-Choco
        Enable-Hyper-V
        Enable-Wsl
        Restart-Computer
    } catch {
        Write-Error "Script error: $_"
    }
} else {
    Write-Error "Please update your windows version at least to 2004 (build version 19041)"
}
