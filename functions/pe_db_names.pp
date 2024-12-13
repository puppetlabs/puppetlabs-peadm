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

  $pe_2025_or_later = SemVerRange('>= 2025.0.0')
  $pe_2023_8_or_later = SemVerRange('>= 2023.8.0')

  case $pe_ver {
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
