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

if (puppet.bat --version | Select-String -Pattern "^5") {
    Write-Host 
    Write-Host "Puppet 5.x detected, setting certificate_revocation to leaf to facilitate migration..."
    puppet.bat config set --section main certificate_revocation leaf
}

Write-Host 
Write-Host "Pointing Puppet Agent to new PE server..."
puppet.bat config delete --section main server
puppet.bat config delete --section agent server
puppet.bat config delete --section main server_list
puppet.bat config delete --section agent server_list
puppet.bat config set --section agent server $PT_target_pe

Write-Host 
Write-Host "Performing initial Puppet Agent run..."
puppet.bat agent --no-daemonize --onetime --no-usecacheonfailure --no-splay  2>&1

Write-Host 
Write-Host "Starting the Puppet Agent service..."
Start-Service puppet