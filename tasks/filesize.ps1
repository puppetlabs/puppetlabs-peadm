# filesize.ps1
Param( 
  $path 
) 
try {
    # Get the File
    $File = Get-Item $path 
    # Get the File Size
    $size = $File.Length

    # Output a JSON result for ease of Task usage in Puppet Task Plans
    if (-eq $size "null") {
        echo '{ "size": null }'
    }else{
        echo '{ "size": "'$size'" }'
    }
}catch {
  Write-Host "Installer failed with Exception: $_.Exception.Message"
  Exit 1
}