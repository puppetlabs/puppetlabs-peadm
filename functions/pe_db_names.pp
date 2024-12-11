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
  case $pe_ver {
    # The patching service was added in 2025.0.0
    SemVerRange('>= 2025.0.0'): {
      $original_db_names + [
        'pe-hac',
        'pe-patching',
      ]
    }

    # The host-action-collector (hac) was added in 2023.8
    SemVerRange('>= 2023.8.0'): {
      $original_db_names + [ 'pe-hac' ]
    }

    default: {
      $original_db_names
    }
  }
}
