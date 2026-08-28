function peadm::pe_db_names (
  String $pe_ver,
) >> Array {
  $original_db_names = [
    'pe-activity',
    'pe-classifier',
    'pe-inventory',
    'pe-orchestrator',
    'pe-rbac',
  ]

  $pe_2026_or_later = SemVerRange('>= 2026.0.0')
  $pe_2025_6_or_later = SemVerRange('>=2025.6.0')
  $pe_2025_3_or_later = SemVerRange('>= 2025.3.0')
  $pe_2025_or_later = SemVerRange('>= 2025.0.0')
  $pe_2023_8_or_later = SemVerRange('>= 2023.8.0')

  case $pe_ver {
    # code-manager gained a database in 2026.0.0
    $pe_2026_or_later: {
      $original_db_names + [
        'pe-hac',
        'pe-patching',
        'pe-infra-assistant',
        'pe-workflow',
        'pe-code-manager',
      ]
    }

    # The workflow service was added in 2025.6.0
    $pe_2025_6_or_later: {
      $original_db_names + [
        'pe-hac',
        'pe-patching',
        'pe-infra-assistant',
        'pe-workflow',
      ]
    }

    # The infra-assistant was added in 2025.3.0
    $pe_2025_3_or_later: {
      $original_db_names + [
        'pe-hac',
        'pe-patching',
        'pe-infra-assistant',
      ]
    }

    # The patching service was added in 2025.0.0
    $pe_2025_or_later: {
      $original_db_names + [
        'pe-hac',
        'pe-patching',
      ]
    }

    # The host-action-collector (hac) was added in 2023.8
    $pe_2023_8_or_later: {
      $original_db_names + ['pe-hac']
    }

    # New branches of this case statement should be added at the top of the stack,
    # since they are all open-ended ranges, and the newest must be checked first,
    # so it doesn't match an outdated version incorrectly.
    default: {
      $original_db_names
    }
  }
}
