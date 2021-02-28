function Get-File-By-Url([String] $url,[String] $filename) {
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $url -OutFile $filename -UseBasicParsing
    } catch {
        Throw $_
    }
}

function Remove-File($filename) {
    $completePath = '.\' + $filename
    Remove-Item $completePath -Recurse -Force -Confirm:$false
}

function Install-Wsl2 {
    Write-Information -MessageData "----------------------------------Install Wsl 2----------------------------------" -InformationAction Continue
    $filename = 'wsl_update_x64.msi'
    try {
        Get-File-By-Url https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi $filename
        Start-Process -Wait -FilePath msiexec -ArgumentList /i, "wsl_update_x64.msi", /passive
        wsl --set-default-version 2
    } catch {
        Throw $_
    } finally {
        Remove-File $filename
    }
}

function Install-Ubuntu-2004 {
    Write-Information -MessageData "----------------------------------Install Ubuntu 20.04----------------------------------" -InformationAction Continue
    $filename = 'Ubuntu-2004.appx'
    try {
        Get-File-By-Url https://aka.ms/wslubuntu2004 $filename
        Add-AppxPackage .\Ubuntu-2004.appx
    } catch {
        Write-Error "Attempt to retrieve the Ubuntu 20.04 fails error: $_"
    } finally {
        Remove-File $filename
    }
}

function Install-Docker {
    Write-Information -MessageData "----------------------------------Install Docker desktop----------------------------------" -InformationAction Continue
    try {
        choco install docker-desktop -y
    } catch {
        Write-Error "Error during the installation of docker-desktop with choco error: $_"
    }
}

function Install-Vs-Code {
   Write-Information -MessageData "----------------------------------Install Vs Code----------------------------------" -InformationAction Continue
   try {
        choco install vscode
   } catch {
        Write-Error "Error during the installation of Visual studio code with choco error: $_"
   }
}

function Add-Wsl-Config {
    Write-Information -MessageData "----------------------------------Create file wsl config----------------------------------" -InformationAction Continue
    $usersDirectory = $env:USERPROFILE;
    $fileContent = "[wsl2]`nmemory=10GB`nswap=4GB`nlocalhostForwarding=true"
    New-Item -Path $usersDirectory -Name ".wslconfig" -ItemType "file" -Value $fileContent
}

function Install-Carbon-Utility {
    Write-Information -MessageData "----------------------------------Install Carbon Utility to handle hosts----------------------------------" -InformationAction Continue
   try {
        choco install carbon
        Import-Module 'Carbon'
        $programFilesPath = Get-ChildItem Env:ProgramFiles;
        $carbonImportScriptPath = $programFilesPath + '\WindowsPowerShell\Modules\Carbon\Import-Carbon.ps1';
        powershell.exe -noprofile -executionpolicy bypass -file $carbonImportScriptPath
   } catch {
        Write-Error "Error during the installation of Carbon with choco error: $_"
   }
}

if ((Get-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V-All -Online).State -eq 'Enabled') {
    try {
        Install-Wsl2
        Install-Ubuntu-2004
        Install-Docker
        Install-Vs-Code
        Add-Wsl-Config
        Install-Carbon-Utility
        Restart-Computer
    } catch {
        Write-Error "Script error: $_"
    }
} else {
    Write-Error "Please run the EnableHyperVAndWsl.ps1 script before this"
}
