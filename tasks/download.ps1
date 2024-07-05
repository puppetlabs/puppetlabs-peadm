# download.ps1
Param( 
    $source,
    $path
)

try {
  [Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}; $webClient = New-Object System.Net.WebClient; $webClient.DownloadFile($source, $path);
}catch {
  Write-Host "Installer failed with Exception: $_.Exception.Message"
  Exit 1
}
