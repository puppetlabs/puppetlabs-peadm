# dowload.ps1
Param( 
    $source
    $path
)
try {
    # Get the File and place in the path
   Invoke-WebRequest $source -OutFile $path
}catch {
  Write-Host "Installer failed with Exception: $_.Exception.Message"
  Exit 1
}