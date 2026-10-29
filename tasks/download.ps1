# download.ps1
Param( 
    $source,
    $path
)

try {
  # TODO PE-47902: this callback accepts any TLS certificate, so the installer can be swapped in transit.
  [Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}; $webClient = New-Object System.Net.WebClient; $webClient.DownloadFile($source, $path);
}catch {
  Write-Host "Installer failed with Exception: $_.Exception.Message"
  Exit 1
}
