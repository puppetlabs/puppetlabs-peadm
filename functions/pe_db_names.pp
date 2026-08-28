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

  # Each case below is an open-ended range, so the newest release must be
  # matched first: a 2026.x version satisfies '>= 2025.6.0' too, and would
  # otherwise fall through to the 2025.6 set and lose 'pe-code-manager'.
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

    default: {
      $original_db_names
    }
  }
}
