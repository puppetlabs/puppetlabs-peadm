# @summary Assert that the architecture given is a supported one
function peadm::assert_supported_architecture (
  TargetSpec                 $primary_host,
  Variant[TargetSpec, Undef] $replica_host = undef,
  Variant[TargetSpec, Undef] $primary_postgresql_host = undef,
  Variant[TargetSpec, Undef] $replica_postgresql_host = undef,
  Variant[TargetSpec, Undef] $compiler_hosts = undef,
  Variant[TargetSpec, Undef] $legacy_compilers = undef,
)  >> Hash {
  # Normalize $legacy_compilers to an array
  $legacy_compilers_array = $legacy_compilers ? {
    undef   => [],
    String  => [$legacy_compilers],
    Array   => $legacy_compilers,
    default => fail("Unexpected type for \$legacy_compilers: ${legacy_compilers}"),
  }

  # Normalize $compiler_hosts to an array
  $compiler_hosts_array = $compiler_hosts ? {
    undef   => [],
    String  => [$compiler_hosts],
    Array   => $compiler_hosts,
    default => fail("Unexpected type for \$compiler_hosts: ${compiler_hosts}"),
  }
  $all_compilers = $legacy_compilers_array + $compiler_hosts_array

  # Set $has_compilers to undef if $all_compilers is empty, otherwise set it to true
  $has_compilers = empty($all_compilers) ? {
    true    => undef,
    default => true,
  }

  $result = case [
    !!($primary_host),
    !!($replica_host),
    !!($primary_postgresql_host),
    !!($replica_postgresql_host),
  ] {
    [true, false, false, false]: { # Standard or Large, no DR
      ({ 'disaster-recovery' => false, 'architecture' => $has_compilers ? {
            undef   => 'standard',
            default => 'large',
      } })
    }
    [true, true, false, false]: { # Standard or Large, DR
      ({ 'disaster-recovery' => true, 'architecture' => $has_compilers ? {
            undef   => 'standard',
            default => 'large',
      } })
    }
    [true, false, true, false]: { # Extra Large, no DR
      ({ 'disaster-recovery' => false, 'architecture' => 'extra-large' })
    }
    [true, true, true, true]: { # Extra Large, DR
      ({ 'disaster-recovery' => true,  'architecture' => 'extra-large' })
    }
# lint:ignore:strict_indent
    default: { # Invalid
      out::message(inline_epp(@(HEREDOC)))
                Invalid architecture! Received:
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
        <% if $has_compilers { -%>
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
# lint:endignore
  # Return value
  return({ 'supported' => true } + $result)
}
