# @api private
# @summary Configures PEAdm's required node groups
#
# This class is not intended to be continously enforced on PE primaries.
# Rather, it describes state to enforce as a boostrap action, preparing the
# Puppet Enterprise console with a sane default environment configuration.
#
# This class will be applied during primary bootstrap using e.g.
#
#     puppet apply \
#       --exec 'class { "peadm::setup::node_manager":
#                 environments => ["production", "staging", "development"],
#               }'
#
# @param compiler_pool_address
#   The service address used by agents to connect to compilers, or the Puppet
#   service. Typically this is a load balancer.
# @param internal_compiler_a_pool_address
#   A load balancer address directing traffic to any of the "A" pool
#   compilers. This is used for DR configuration in large and extra large
#   architectures.
# @param internal_compiler_b_pool_address
#   A load balancer address directing traffic to any of the "B" pool
#   compilers. This is used for DR configuration in large and extra large
#   architectures.
# @param node_group_environment the environment that will be assigned to all the PE Infra node groups
# @param cloud_database_host
#   When set, declares that PE's PostgreSQL database is hosted externally at
#   the given host (e.g. Google Cloud SQL). The PE Database node group is
#   not created (the cloud endpoint is not a PEADM-managed target), the
#   puppet_enterprise::profile::puppetdb entry is omitted from the PE
#   Primary A and PE Primary B classifier config_data (the cloud DB host is
#   expected to be authoritatively declared in pe_install's PE PuppetDB
#   classifier group instead), and the puppet_enterprise::profile::puppetdb
#   database_host class parameter on PE Compiler Group A/B is set to this
#   value so compilers reach the external database. Leave unset for the
#   default on-prem topology.
#
class peadm::setup::node_manager (
  String[1] $primary_host,

  Optional[String[1]] $server_a_host                    = undef,
  Optional[String[1]] $server_b_host                    = undef,

  String[1]           $postgresql_a_host                = $server_a_host,
  Optional[String[1]] $postgresql_b_host                = $server_b_host,

  Optional[String[1]] $compiler_pool_address            = undef,
  Optional[String[1]] $internal_compiler_a_pool_address = $server_a_host,
  Optional[String[1]] $internal_compiler_b_pool_address = $server_b_host,
  String[1]           $node_group_environment           = 'production',

  Optional[Stdlib::Host] $cloud_database_host           = undef,
) {
  # "Not-configured" placeholder string. This will be used in places where we
  # cannot set an explicit null, and need to supply some kind of value.
  $notconf = 'not-configured'

  # Preserve existing user data and classes values. We only need to make sure
  # the values we care about are present; we don't need to remove anything
  # else.
  Node_group {
    purge_behavior => none,
    environment    => $node_group_environment,
  }

  ##################################################
  # PE INFRASTRUCTURE GROUPS
  ##################################################

  # We modify this group's rule such that all PE infrastructure nodes will be
  # members.
  node_group { 'PE Infrastructure Agent':
    purge_behavior => rule,
    rule           => ['or',
      ['~', ['trusted', 'extensions', peadm::oid('peadm_role')], '^puppet/'],
      ['~', ['fact', 'pe_server_version'], '.+']
    ],
  }

  # We modify PE Master to add, as data, the compiler_pool_address only. Some
  # users may set this value via Hiera, so we don't want to always require it
  # being set in the console.
  $compiler_pool_address_data = $compiler_pool_address ? {
    undef   => undef,
    default => { 'pe_repo' => { 'compile_master_pool_address' => $compiler_pool_address } },
  }

  # We do not call this node group PE Primary because it is modifying a
  # built-in group, rather than creating a new one. And, as of PE 2021.1, the
  # name is still PE Master.
  node_group { 'PE Master':
    parent    => 'PE Infrastructure',
    data      => $compiler_pool_address_data,
    variables => { 'pe_master' => true },
  }

  # PE Compiler group comes from default PE and already has the pe compiler role
  node_group { 'PE Compiler':
    parent         => 'PE Master',
    purge_behavior => 'rule',
    rule           => ['and', ['=', ['trusted', 'extensions', 'pp_auth_role'], 'pe_compiler']],
  }

  # This group should pin the primary, and also map to any pe-postgresql nodes
  # which are part of the architecture. When PE's database is hosted externally
  # (cloud_database_host is set), there is no PEADM-managed Postgres node to
  # classify here, so the group is omitted entirely.
  unless $cloud_database_host {
    node_group { 'PE Database':
      rule => ['or',
        ['and', ['=', ['trusted', 'extensions', peadm::oid('peadm_role')], 'puppet/puppetdb-database']],
        ['=', 'name', $primary_host],
      ],
    }
  }

  # Create data-only groups to store PuppetDB PostgreSQL database configuration
  # information specific to the primary and primary replica nodes.
  #
  # In cloud database mode, the puppet_enterprise::profile::puppetdb entry is
  # omitted from this group's config_data. The authoritative cloud DB host
  # belongs in pe_install's PE PuppetDB classifier group; if PEADM also writes
  # it via config_data here, the two declarations conflict in the classifier's
  # flattened resolution view. The adjacent primary_master_replica
  # database_host_puppetdb entry still tells the replica where PuppetDB's
  # database lives, so it carries the cloud DB host instead.
  # On-prem: only a dedicated pe-postgresql node (Extra Large) hosts PuppetDB's
  # database remotely. When the database is co-located with the PuppetDB server
  # -- there is no separate postgresql host, or the postgresql host IS the server
  # itself -- leave database_host UNSET so PE provisions and uses the LOCAL
  # database. Emitting a non-undef value here (the server's own host, or the
  # 'not-configured' sentinel) makes PE 2025.11+ treat the co-located database as
  # remote and never create the local pe-puppetdb database, so pe-puppetdb fails
  # to start (900s startup timeout).
  $puppetdb_database_host_a = ($postgresql_a_host =~ NotUndef and $postgresql_a_host != $server_a_host) ? {
    true    => $postgresql_a_host,
    default => undef,
  }
  $primary_a_data = $cloud_database_host ? {
    undef   => $puppetdb_database_host_a ? {
      undef   => {},
      default => {
        'puppet_enterprise::profile::primary_master_replica' => {
          'database_host_puppetdb' => $puppetdb_database_host_a,
        },
        'puppet_enterprise::profile::puppetdb'               => {
          'database_host' => $puppetdb_database_host_a,
        },
      },
    },
    default => {
      'puppet_enterprise::profile::primary_master_replica' => {
        'database_host_puppetdb' => $cloud_database_host,
      },
    },
  }

  node_group { 'PE Primary A':
    ensure => present,
    parent => 'PE Infrastructure',
    rule   => ['and',
      ['=', ['trusted', 'extensions', peadm::oid('peadm_role')], 'puppet/server'],
      ['=', ['trusted', 'extensions', peadm::oid('peadm_availability_group')], 'A'],
    ],
    data   => $primary_a_data,
  }

  # Compilers must know where puppetdb's database lives to talk to it directly.
  # When a cloud database host is supplied, prefer it; otherwise fall back to
  # the existing postgresql_a_host value.
  $compiler_a_puppetdb_database_host = pick($cloud_database_host, $postgresql_a_host, $notconf)

  # Configure the A pool for compilers. There are up to two pools for DR, each
  # having an affinity for one "availability zone" or the other.
  node_group { 'PE Compiler Group A':
    ensure         => 'present',
    purge_behavior => 'rule',
    parent         => 'PE Compiler',
    rule           => ['and',
      ['=', ['trusted', 'extensions', 'pp_auth_role'], 'pe_compiler'],
      ['=', ['trusted', 'extensions', peadm::oid('peadm_availability_group')], 'A'],
    ],
    classes        => {
      'puppet_enterprise::profile::puppetdb' => {
        'database_host' => $compiler_a_puppetdb_database_host,
      },
      'puppet_enterprise::profile::master'   => {
        # lint:ignore:single_quote_string_with_variables
        'puppetdb_host' => ['${trusted[\'certname\']}', $internal_compiler_b_pool_address].filter |$_| { $_ },
        # lint:endignore
        'puppetdb_port' => [8081],
      },
    },
    data           => {
      # Workaround for GH-118
      'puppet_enterprise::profile::master::puppetdb' => {
        'ha_enabled_replicas' => [],
      },
    },
  }

  # Always create the replica and B groups, even if a replica primary and
  # database host are not supplied. This consistency enables the
  # peadm::get_cluster_roles task to reliably return the currently configured
  # PEAdm roles.

  # We need to ensure this group provides the peadm_replica variable.
  node_group { 'PE HA Replica':
    ensure    => 'present',
    parent    => 'PE Infrastructure',
    classes   => {
      'puppet_enterprise::profile::primary_master_replica' => {},
    },
    variables => { 'peadm_replica' => true },
  }

  # See PE Primary A above; the same co-located/dedicated/cloud treatment applies
  # to the B availability group (the replica). The replica's PuppetDB database is
  # co-located ($postgresql_b_host is unset, or equals the replica itself), so
  # database_host is left UNSET and PE creates the replica's LOCAL pe-puppetdb
  # database. Only a dedicated pe-postgresql node (XL) yields an explicit host.
  $puppetdb_database_host_b = ($postgresql_b_host =~ NotUndef and $postgresql_b_host != $server_b_host) ? {
    true    => $postgresql_b_host,
    default => undef,
  }
  $primary_b_data = $cloud_database_host ? {
    undef   => $puppetdb_database_host_b ? {
      undef   => {},
      default => {
        'puppet_enterprise::profile::primary_master_replica' => {
          'database_host_puppetdb' => $puppetdb_database_host_b,
        },
        'puppet_enterprise::profile::puppetdb'               => {
          'database_host' => $puppetdb_database_host_b,
        },
      },
    },
    default => {
      'puppet_enterprise::profile::primary_master_replica' => {
        'database_host_puppetdb' => $cloud_database_host,
      },
    },
  }

  node_group { 'PE Primary B':
    ensure => present,
    parent => 'PE Infrastructure',
    rule   => ['and',
      ['=', ['trusted', 'extensions', peadm::oid('peadm_role')], 'puppet/server'],
      ['=', ['trusted', 'extensions', peadm::oid('peadm_availability_group')], 'B'],
    ],
    data   => $primary_b_data,
  }

  $compiler_b_puppetdb_database_host = pick($cloud_database_host, $postgresql_b_host, $notconf)

  node_group { 'PE Compiler Group B':
    ensure         => 'present',
    purge_behavior => 'rule',
    parent         => 'PE Compiler',
    rule           => ['and',
      ['=', ['trusted', 'extensions', 'pp_auth_role'], 'pe_compiler'],
      ['=', ['trusted', 'extensions', peadm::oid('peadm_availability_group')], 'B'],
    ],
    classes        => {
      'puppet_enterprise::profile::puppetdb' => {
        'database_host' => $compiler_b_puppetdb_database_host,
      },
      'puppet_enterprise::profile::master'   => {
        # lint:ignore:single_quote_string_with_variables
        'puppetdb_host' => ['${trusted[\'certname\']}', $internal_compiler_a_pool_address].filter |$_| { $_ },
        # lint:endignore
        'puppetdb_port' => [8081],
      },
    },
    data           => {
      # Workaround for GH-118
      'puppet_enterprise::profile::master::puppetdb' => {
        'ha_enabled_replicas' => [],
      },
    },
  }

  node_group { 'PE Legacy Compiler':
    parent         => 'PE Master',
    purge_behavior => 'rule',
    rule           => ['=', ['trusted', 'extensions', 'pp_auth_role'], 'pe_compiler_legacy'],
    classes        => {
      'puppet_enterprise::profile::master'   => {
        'puppetdb_host' => [$internal_compiler_a_pool_address, $internal_compiler_b_pool_address].filter |$_| { $_ }.unique,
        'puppetdb_port' => [8081],
      },
    },
  }

  # Configure the A pool for legacy compilers. There are up to two pools for DR, each
  # having an affinity for one "availability zone" or the other.
  node_group { 'PE Legacy Compiler Group A':
    ensure         => 'present',
    parent         => 'PE Legacy Compiler',
    purge_behavior => 'rule',
    rule           => ['and',
      ['=', ['trusted', 'extensions', 'pp_auth_role'], 'pe_compiler_legacy'],
      ['=', ['trusted', 'extensions', peadm::oid('peadm_availability_group')], 'A'],
    ],
    classes        => {
      'puppet_enterprise::profile::master'   => {
        'puppetdb_host' => [$internal_compiler_b_pool_address, $internal_compiler_a_pool_address].filter |$_| { $_ }.unique,
        'puppetdb_port' => [8081],
      },
    },
    data           => {
      # Workaround for GH-118
      'puppet_enterprise::profile::master::puppetdb' => {
        'ha_enabled_replicas' => [],
      },
    },
  }

  # Configure the B pool for legacy compilers. There are up to two pools for DR, each
  # having an affinity for one "availability zone" or the other.
  node_group { 'PE Legacy Compiler Group B':
    ensure         => 'present',
    parent         => 'PE Legacy Compiler',
    purge_behavior => 'rule',
    rule           => ['and',
      ['=', ['trusted', 'extensions', 'pp_auth_role'], 'pe_compiler_legacy'],
      ['=', ['trusted', 'extensions', peadm::oid('peadm_availability_group')], 'B'],
    ],
    classes        => {
      'puppet_enterprise::profile::master'   => {
        'puppetdb_host' => [$internal_compiler_a_pool_address, $internal_compiler_b_pool_address].filter |$_| { $_ }.unique,
        'puppetdb_port' => [8081],
      },
    },
    data           => {
      # Workaround for GH-118
      'puppet_enterprise::profile::master::puppetdb' => {
        'ha_enabled_replicas' => [],
      },
    },
  }
}
