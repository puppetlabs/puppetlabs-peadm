# filesize.ps1
Param( 
  $path 
) 
if ([string]::IsNullOrEmpty($path)){
    Write-Host "No path provided to filesize"
    Exit 1
}
try {

    # Get the File
    $File = Get-Item -Path $path 
    # Get the File Size
    $size = $File.Length

    # Output a JSON result for ease of Task usage in Puppet Task Plans
    if ($size -eq $null) {
        Write-Host "{'size': '$null'}"
    }else{
        Write-Host "{'size': '$size'}"
    }

    return $size
    
}catch {
  Write-Host "Installer failed with Exception: $_.Exception.Message"
  Exit 1
}
