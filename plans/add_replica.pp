# @summary Add or replace a replica host.
#   Supported use cases:
#   1: Adding a replica to an existing primary.
#   2: The existing replica is broken, we have a fresh new VM we want to provision the replica to.
# @param primary_host - The hostname and certname of the primary Puppet server
# @param replica_host - The hostname and certname of the replica VM
# @param replica_postgresql_host - The hostname and certname of the host with the replica PE-PosgreSQL database.
#   Can be a separate host in an XL architecture, or undef in Standard or Large.
# @param token_file - (optional) the token file in a different location than the default.
# @param node_group_environment environment for the PEADM specific node groups, if not set it will be gathered from pe.conf or production
plan peadm::add_replica(
  # Standard or Large
  Peadm::SingleTargetSpec           $primary_host,
  Peadm::SingleTargetSpec           $replica_host,

  # Extra Large
  Optional[Peadm::SingleTargetSpec] $replica_postgresql_host = undef,

  # Common Configuration
  Optional[String] $token_file = undef,
  String[1] $node_group_environment = peadm::get_node_group_environment($primary_host),
) {
  $primary_target             = peadm::get_targets($primary_host, 1)
  $replica_target             = peadm::get_targets($replica_host, 1)
  $replica_postgresql_target  = peadm::get_targets($replica_postgresql_host, 1)

  $code_manager_enabled = run_task('peadm::code_manager_enabled', $primary_target).first.value['code_manager_enabled']

  if $code_manager_enabled == false {
    fail('Code Manager must be enabled to add a replica. Please refer to the docs for more information on enabling Code Manager.')
  }

  run_command('systemctl stop puppet.service', peadm::flatten_compact([
        $primary_target,
        $replica_postgresql_target,
  ]))

  # Get current peadm config to ensure we forget active replicas
  $peadm_config = run_task('peadm::get_peadm_config', $primary_target).first.value

  # Make list of all possible replicas, configured and provided
  $replicas = peadm::flatten_compact([
      $replica_host,
      $peadm_config['params']['replica_host'],
  ]).unique

  $certdata = run_task('peadm::cert_data', $primary_target).first.value
  $primary_avail_group_letter = $certdata['extensions'][peadm::oid('peadm_availability_group')]
  $replica_avail_group_letter = $primary_avail_group_letter ? { 'A' => 'B', 'B' => 'A' }

  # replica certname + any non-certname alt-names from the primary. Make sure
  # to Handle the case where there are no alt-names in the primary's certdata.
  $dns_alt_names = [$replica_target.peadm::certname()] + (pick($certdata['dns-alt-names'], []) - $certdata['certname'])

  # This has the effect of revoking the node's certificate, if it exists
  $replicas.each |$replica| {
    run_command("/opt/puppetlabs/bin/puppet infrastructure forget ${replica}", $primary_target, _catch_errors => true)
  }

  run_plan('peadm::subplans::component_install', $replica_target,
    primary_host       => $primary_target,
    avail_group_letter => $replica_avail_group_letter,
    role               => 'puppet/server',
    dns_alt_names      => $dns_alt_names
  )

  # Wrap these things that operate on replica_postgresql_target in an if statement
  # to avoid failures retrieving PSQL version because you can't operate functions
  # on a return value of nil.
  if $replica_postgresql_host {
    # On the PE-PostgreSQL server in the <replacement-avail-group-letter> group
    $psql_version = run_task('peadm::get_psql_version', $replica_postgresql_target).first.value['version']

    # Stop puppet and add the following two lines to
    # /opt/puppetlabs/server/data/postgresql/11/data/pg_ident.conf
    #  pe-puppetdb-pe-puppetdb-map <replacement-replica-fqdn> pe-puppetdb
    #  pe-puppetdb-pe-puppetdb-migrator-map <replacement-replica-fqdn> pe-puppetdb-migrator
    apply($replica_postgresql_target) {
      file_line { 'pe-puppetdb-pe-puppetdb-map':
        path => "/opt/puppetlabs/server/data/postgresql/${psql_version}/data/pg_ident.conf",
        line => "pe-puppetdb-pe-puppetdb-map ${replica_target.peadm::certname()} pe-puppetdb",
      }
      file_line { 'pe-puppetdb-pe-puppetdb-migrator-map':
        path => "/opt/puppetlabs/server/data/postgresql/${psql_version}/data/pg_ident.conf",
        line => "pe-puppetdb-pe-puppetdb-migrator-map ${replica_target.peadm::certname()} pe-puppetdb-migrator",
      }
      file_line { 'pe-puppetdb-pe-puppetdb-read-map':
        path => "/opt/puppetlabs/server/data/postgresql/${psql_version}/data/pg_ident.conf",
        line => "pe-puppetdb-pe-puppetdb-read-map ${replica_target.peadm::certname()} pe-puppetdb-read",
      }
    }

    run_command('systemctl reload pe-postgresql.service', $replica_postgresql_target)
  }

  run_plan('peadm::util::update_classification', $primary_target,
    server_a_host                    => $replica_avail_group_letter ? { 'A' => $replica_target.peadm::certname(), default => undef },
    server_b_host                    => $replica_avail_group_letter ? { 'B' => $replica_target.peadm::certname(), default => undef },
    internal_compiler_a_pool_address => $replica_avail_group_letter ? { 'A' => $replica_target.peadm::certname(), default => undef },
    internal_compiler_b_pool_address => $replica_avail_group_letter ? { 'B' => $replica_target.peadm::certname(), default => undef },
    peadm_config                     => $peadm_config,
    node_group_environment           => $node_group_environment,
  )

  # Source list of files on Primary and synchronize to new Replica
  $content_sources = [
    '/opt/puppetlabs/server/data/console-services/certs/ad_ca_chain.pem',
    '/etc/puppetlabs/orchestration-services/conf.d/secrets/keys.json',
    '/etc/puppetlabs/orchestration-services/conf.d/secrets/orchestrator-encryption-keys.json',
    '/etc/puppetlabs/console-services/conf.d/secrets/keys.json',
    '/etc/puppetlabs/puppet/hiera.yaml',
  ]
  parallelize($content_sources) |$path| {
    run_plan('peadm::util::copy_file', $replica_target,
      source_host   => $primary_target,
      path          => $path
    )
  }

  # Provision the new system as a replica. The installer's orchestrated job
  # occasionally fails with a transient "ConnectionClosedException" from the
  # orchestration service while it runs Puppet on the primary -- the primary
  # appears to bounce its own orchestration service mid-job. A second
  # variant of the same race surfaces as "Connection refused"/"Failed to
  # open TCP connection" on port 8143 -- the orchestration service hasn't
  # started listening yet when provision_replica's own internal CLI tries
  # to reach it. Retry a bounded number of times to ride out either race;
  # any other failure (e.g. a bad token, or a genuine provisioning error)
  # is not retried and surfaces on the first attempt.
  #
  # Provisioning and enabling are split into two separate task calls (rather
  # than the atomic provision --enable used before) because PE core's
  # --enable path runs its own replica service-health check with a short,
  # fixed wait (~21s observed) after reinitializing the replica's
  # Classifier/RBAC/PuppetDB. In CI that wait is consistently too short --
  # confirmed by seeing the identical "These services are not running"
  # failure on every one of 3 full re-provision attempts, not just an
  # occasional one -- so retrying the atomic call doesn't help. Splitting
  # the call lets peadm poll for readiness itself via
  # peadm::wait_until_service_ready, which allows up to 60s, before telling
  # PE core to enable the replica.
  $provision_replica_max_attempts = 3
  $provision_result = range(1, $provision_replica_max_attempts).reduce(undef) |$memo, $attempt| {
    $prior_output = ($memo =~ NotUndef and !$memo.ok and $memo.error_set.first.value =~ Hash) ? {
      true    => $memo.error_set.first.value['_output'],
      default => undef,
    }
    # "Service is not running" (for RBAC, Classifier, Orchestrator, PuppetDB,
    # PCP Broker, etc.) shows up here when the primary's own cert was just
    # regenerated (see peadm::subplans::modify_certificate's reactive
    # cert-reissue): only pe-puppetserver gets restarted as part of that
    # regen, so the other co-located services can still be holding
    # connections/trust state built against the old cert for a few more
    # seconds even though peadm::wait_until_service_ready('all', ...)
    # already reported puppetserver itself as ready. Treat it as transient
    # and retry, the same as the orchestrator connection races below.
    $prior_is_transient = ($prior_output =~ String[1]) and ($prior_output =~ /ConnectionClosedException|puppetlabs\.orchestrator\/unknown-error|Connection refused|Failed to open TCP connection|is not running/)

    if $memo =~ NotUndef and ($memo.ok or !$prior_is_transient) {
      $memo
    } else {
      if $attempt > 1 {
        out::message("provision_replica hit a transient orchestrator error; retrying (attempt ${attempt}/${provision_replica_max_attempts}) after 15s...")
        ctrl::sleep(15)
      }
      run_task('peadm::provision_replica', $primary_target,
        replica       => $replica_target.peadm::certname(),
        token_file    => $token_file,
        legacy        => false,
        action        => 'provision',
        _catch_errors => true,
      )
    }
  }

  # Surface real provisioning failures instead of masking them. Without this
  # check, errors caught by _catch_errors are silently dropped and the plan
  # reports success regardless. See PE-43490.
  unless $provision_result.ok {
    $errors = $provision_result.error_set.map |$result| {
      # Surface the task's real output rather than Bolt's generic
      # "task failed with exit code N". provision_replica shells out to
      # `puppet infrastructure provision replica`; the actual error text
      # only appears in the task's captured output (_output).
      $result_value = $result.value
      $output = ($result_value =~ Hash) ? { true => $result_value['_output'], default => undef }
      $detail = ($output =~ String[1]) ? { true => $output, default => $result.error.message }
      "${result.target.name}: ${detail}"
    }.join("\n\n")

    # Only point at RBAC tokens when the underlying error actually looks like
    # a token/authorization problem -- otherwise this hint is misleading
    # noise next to the real cause (e.g. an orchestrator timeout or a
    # pg_basebackup failure).
    $token_hint = ($errors =~ /(?i:token|401|unauthorized|rbac)/) ? {
      true    => "\n\nA missing or expired RBAC token (default ~/.puppetlabs/token, or the\ntoken_file parameter) is one common cause.",
      default => '',
    }

    fail_plan(@("MSG"))
      peadm::provision_replica failed; the replica was not provisioned. Underlying error:

      ${errors}

      See the provision_replica CLI log under /var/log/puppetlabs/installer/ on the
      primary for the full output.${token_hint}
      | MSG
  }

  # Give the replica's Classifier/RBAC/PuppetDB real time to come up before
  # asking PE core to enable it -- see comment above the retry loop.
  peadm::wait_until_service_ready('pe-master', $replica_target)

  $enable_replica_max_attempts = 3
  $enable_result = range(1, $enable_replica_max_attempts).reduce(undef) |$memo, $attempt| {
    $prior_output = ($memo =~ NotUndef and !$memo.ok and $memo.error_set.first.value =~ Hash) ? {
      true    => $memo.error_set.first.value['_output'],
      default => undef,
    }
    $prior_is_transient = ($prior_output =~ String[1]) and ($prior_output =~ /ConnectionClosedException|puppetlabs\.orchestrator\/unknown-error|Connection refused|Failed to open TCP connection/)

    if $memo =~ NotUndef and ($memo.ok or !$prior_is_transient) {
      $memo
    } else {
      if $attempt > 1 {
        out::message("enable_replica hit a transient orchestrator error; retrying (attempt ${attempt}/${enable_replica_max_attempts}) after 15s...")
        ctrl::sleep(15)
      }
      run_task('peadm::provision_replica', $primary_target,
        replica       => $replica_target.peadm::certname(),
        token_file    => $token_file,
        legacy        => false,
        action        => 'enable',
        _catch_errors => true,
      )
    }
  }

  unless $enable_result.ok {
    $enable_errors = $enable_result.error_set.map |$result| {
      $result_value = $result.value
      $output = ($result_value =~ Hash) ? { true => $result_value['_output'], default => undef }
      $detail = ($output =~ String[1]) ? { true => $output, default => $result.error.message }
      "${result.target.name}: ${detail}"
    }.join("\n\n")

    fail_plan(@("MSG")/L)
      peadm::provision_replica (enable) failed; the replica was provisioned but not enabled. \
      Underlying error:

      ${enable_errors}

      See the provision_replica CLI log under /var/log/puppetlabs/installer/ on the
      primary for the full output.
      | MSG
  }

  # start puppet service
  run_command('systemctl start puppet.service', peadm::flatten_compact([
        $primary_target,
        $replica_postgresql_target,
        $replica_target,
  ]))

  return("Added replica ${replica_target}")
}
