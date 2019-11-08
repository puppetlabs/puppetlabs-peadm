function pe_xl::validate_architecture (
  TargetSpec                 $master_host,
  Variant[TargetSpec, Undef] $master_replica_host = undef,
  Variant[TargetSpec, Undef] $puppetdb_database_host = undef,
  Variant[TargetSpec, Undef] $puppetdb_database_replica_host = undef,
  Variant[TargetSpec, Undef] $compiler_hosts = undef,
)  >> Hash {
  $result = case [
    !!($master_host),
    !!($master_replica_host),
    !!($puppetdb_database_host),
    !!($puppetdb_database_replica_host),
  ] {
    [true, false, false, false]: { # Standard or Large, no HA
      ({ 'high-availability' => false, 'architecture' => $compiler_hosts ? {
        undef   => 'standard',
        default => 'large',
      }})
    }
    [true, true, false, false]: {  # Standard or Large, HA
      ({ 'high-availability' => false, 'architecture' => $compiler_hosts ? {
        undef   => 'standard',
        default => 'large',
      }})
    }
    [true, false, true, false]: {  # Extra Large, no HA
      ({ 'high-availability' => false, 'architecture' => 'extra-large' })
    }
    [true, true, true, true]: {    # Extra Large, HA
      ({ 'high-availability' => true,  'architecture' => 'extra-large' })
    }
    default: {                     # Invalid
      out::message(inline_epp(@(HEREDOC)))
        Invalid architecture! Recieved:
          - master
        <% if $master_replica_host { -%>
          - master-replica
        <% } -%>
        <% if $puppetdb_database_host { -%>
          - pdb-database
        <% } -%>
        <% if $puppetdb_database_replica_host { -%>
          - pdb-database-replica
        <% } -%>
        <% if $compiler_hosts { -%>
          - compilers
        <% } -%>

        Supported architectures include:
          Standard
            - master
          Standard with HA
            - master
            - master-replica
          Large
            - master
            - compilers
          Large with HA
            - master
            - master-replica
            - compilers
          Extra Large
            - master
            - pdb-database
            - compilers (optional)
          Extra Large with HA
            - master
            - master-replica
            - pdb-database
            - pdb-database-replica
            - compilers (optional)
        | HEREDOC

      fail('Invalid architecture!')
    }
  }

  # Return value
  $result
}
