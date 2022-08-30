# agent_install.ps1

if (!(Test-Path "C:\Program Files\Puppet Labs\Puppet\puppet\bin\puppet")){
  Write-Host "ERROR: Puppet agent is already installed. Re-install, re-configuration, or upgrade not supported. Please uninstall the agent before running this task."
  Exit 1
}

$flags=$PT_install_flags -replace '^\["*','' -replace 's/"*\]$','' -replace '/", *"',' '
[Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}; $webClient = New-Object System.Net.WebClient; $webClient.DownloadFile("https://${PT_server}:8140/packages/current/install.ps1", 'install.ps1'); .\install.ps1 $flags