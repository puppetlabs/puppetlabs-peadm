[CmdletBinding()]
Param(
  [String] $target_pe,
  [Boolean] $regenerate = $true
)

# Ensure we can reach the target Puppet Enterprise server
Write-Host "Verifying connectivity to target Puppet server $target_pe:8140..."
if (Test-NetConnection -ComputerName $target_pe -Port 8140 -WarningAction Stop) {
    Write-Host "Target Puppet server is reacheable"
} else {
    Write-Host "Target Puppet server is not reacheable, aborting migration!"
    exit 1
}

Write-Host 
Write-Host "Stopping the Puppet Agent service..."
Stop-Service puppet

if ($regenerate) {
    Write-Host 
    Write-Host "Regenerate flag detected, clearing out existing node certificates before migration..."
    $localcacert = puppet.bat config print localcacert
    $hostcert    = puppet.bat config print hostcert
    $hostprivkey = puppet.bat config print hostprivkey
    $hostpubkey  = puppet.bat config print hostpubkey
    $hostcrl     = puppet.bat config print hostcrl
    $hostcsr     = puppet.bat config print hostcsr
    $collection = $localcacert, $hostcert, $hostprivkey, $hostpubkey, $hostcrl, $hostcsr
    foreach ($item in $collection) {
        if (Test-Path $item -PathType leaf) {
            Write-Host "Deleting $item..."
            Remove-Item $item
        } 
    }
    Write-Host "Existing node certificates have been cleared, new certificates will be generated on the next Puppet run"
}

Write-Host 
Write-Host "Pointing Puppet Agent to new PE server..."
puppet.bat config set server $target_pe

Write-Host 
Write-Host "Installing the new Puppet Agent..."
[System.Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
$webClient = New-Object System.Net.WebClient
$webClient.DownloadFile("https://${target_pe}:8140/packages/current/install.ps1", "$env:TEMP\install.ps1") 2>&1
& $env:TEMP\install.ps1 -v 2>&1

if (-not $?) {
    Write-Host "Installation of new Puppet Agent failed! Check the error for details."
    exit 3
}

Write-Host 
Write-Host "Performing initial Puppet Agent run..."
puppet.bat agent --no-daemonize --onetime --no-usecacheonfailure --no-splay  2>&1

Write-Host 
Write-Host "Starting the Puppet Agent service..."
Start-Service puppet