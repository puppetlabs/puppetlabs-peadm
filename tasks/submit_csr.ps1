Param( 
  $dns_alt_names
)
  if ( C:\"Program Files"\"Puppet Labs"\Puppet\bin\puppet ssl verify ) {
  Write-Host "ERROR: Puppet agent certificate is already signed"
  Exit 1
}else{
  if ($dns_alt_names) {
    $submit_flags = "--dns_alt_names" + ($dns_alt_names -join ',')
  }
  C:\"Program Files"\"Puppet Labs"\Puppet\bin\puppet ssl submit_request $submit_flags
}
