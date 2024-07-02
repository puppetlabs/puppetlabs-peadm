# os_identification.ps1
try {

    $os = [System.Environment]::OSVersion.Platform

    if ($os -eq "Win32NT") {
        $osfamily = "windows"
    }elseif ($os -eq "Unix") {
        $osfamily = "unix"
    }else {
        $osfamily = "unknown"
    }

    return $osfamily
}catch {
  Write-Host "Installer failed with Exception: $_.Exception.Message"
  Exit 1
}
