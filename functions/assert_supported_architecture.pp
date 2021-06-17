function peadm::assert_supported_architecture (
  TargetSpec                 $primary_host,
  Variant[TargetSpec, Undef] $replica_host = undef,
  Variant[TargetSpec, Undef] $primary_postgresql_host = undef,
  Variant[TargetSpec, Undef] $replica_postgresql_host = undef,
  Variant[TargetSpec, Undef] $compiler_hosts = undef,
)  >> Hash {
  $result = case [
    !!($primary_host),
    !!($replica_host),
    !!($primary_postgresql_host),
    !!($replica_postgresql_host),
  ] {
    [true, false, false, false]: { # Standard or Large, no DR
      ({ 'disaster-recovery' => false, 'architecture' => $compiler_hosts ? {
        undef   => 'standard',
        default => 'large',
      }})
    }
    [true, true, false, false]: {  # Standard or Large, DR
      ({ 'disaster-recovery' => true, 'architecture' => $compiler_hosts ? {
        undef   => 'standard',
        default => 'large',
      }})
    }
    [true, false, true, false]: {  # Extra Large, no DR
      ({ 'disaster-recovery' => false, 'architecture' => 'extra-large' })
    }
    [true, true, true, true]: {    # Extra Large, DR
      ({ 'disaster-recovery' => true,  'architecture' => 'extra-large' })
    }
    default: {                     # Invalid
      out::message(inline_epp(@(HEREDOC)))
        Invalid architecture! Recieved:
          - primary
        <% if $replica_host { -%>
          - primary-replica
        <% } -%>
        <% if $primary_postgresql_host { -%>
          - pdb-database
        <% } -%>
        <% if $replica_postgresql_host { -%>
          - pdb-database-replica
        <% } -%>
        <% if $compiler_hosts { -%>
          - compilers
        <% } -%>

        Supported architectures include:
          Standard
            - primary
          Standard with DR
            - primary
            - primary-replica
          Large
            - primary
            - compilers
          Large with DR
            - primary
            - primary-replica
            - compilers
          Extra Large
            - primary
            - pdb-database
            - compilers (optional)
          Extra Large with DR
            - primary
            - primary-replica
            - pdb-database
            - pdb-database-replica
            - compilers (optional)
        | HEREDOC

      fail('Invalid architecture!')
    }
  }

  # Return value
  return({ 'supported' =>  true } + $result)
}
