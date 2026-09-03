# frozen_string_literal: true

# rubocop:disable Layout/LineLength

require 'spec_helper'

describe 'peadm::restore' do
  include BoltSpec::Plans

  backup_dir = '/input/file'
  backup_tarball = "#{backup_dir}.tar.gz"

  let(:recovery_params) do
    {
      'targets'      => 'primary',
      'input_file'   => backup_tarball,
      'restore_type' => 'recovery'
    }
  end
  let(:recovery_db_params) do
    {
      'targets'      => 'primary',
      'input_file'   => backup_tarball,
      'restore_type' => 'recovery-db'
    }
  end
  let(:classifier_only_params) do
    {
      'targets' => 'primary',
      'input_file'   => backup_tarball,
      'restore_type' => 'custom',
      'restore' => {
        'activity'     => false,
        'ca'           => false,
        'classifier'   => true,
        'code'         => false,
        'config'       => false,
        'orchestrator' => false,
        'puppetdb'     => false,
        'rbac'         => false,
      }
    }
  end

  let(:cluster) { { 'params' => { 'primary_host' => 'primary', 'primary_postgresql_host' => 'postgres' } } }

  # PostgreSQL server major version of the restore target. 17 (PE 2025.11)
  # exercises the public-schema owner/USAGE re-grant; override for older PE.
  let(:psql_version) { '17' }

  before(:each) do |example|
    allow_apply

    # Normalize whitespace around `=>` so the expected string matches the plan's
    # single-spaced hash rendering on every Ruby: Ruby 3.4's Hash#to_s already
    # spaces `=>`, older Rubies do not — collapse both to a single ` => `.
    expect_out_message.with_params('cluster: ' + cluster.to_s.delete('"').gsub(%r{\s*=>\s*}, ' => '))
    # Tests tagged `cluster_error: true` exercise the guard that fail_plan()s
    # before this point in the plan is ever reached, so the ldap-secret
    # message never fires there. Without this exclusion, expect_out_message
    # would register an unmet expectation and mask the assertions those tests
    # actually care about.
    unless example.metadata[:cluster_error]
      expect_out_message.with_params('# Restoring ldap secret key if it exists')
    end
    allow_task('peadm::puppet_runonce')
    allow_task('peadm::get_psql_version').always_return({ 'version' => psql_version })
  end

  # only run for tests that have the :valid_cluster tag
  before(:each, valid_cluster: true) do
    expect_task('peadm::get_peadm_config').always_return(cluster)
  end

  it 'runs with recovery params', valid_cluster: true do
    expect_out_message.with_params('# Restoring database pe-puppetdb')
    expect_out_message.with_params('# Restoring ca, certs, code and config for recovery')

    expect_command("umask 0077   && cd /input   && tar -xzf /input/file.tar.gz\n")
    expect_command("/opt/puppetlabs/bin/puppet-backup restore   --scope=certs,code,config   --tempdir=/input/file   --force   /input/file/recovery/pe_backup-*tgz\n")
    expect_command("systemctl stop pe-console-services pe-nginx pxp-agent pe-puppetserver                pe-orchestration-services puppet pe-puppetdb\n")
    expect_command("test -f /input/file/rbac/secrets/keys.json   && cp -rp /input/file/rbac/secrets/keys.json /etc/puppetlabs/console-services/conf.d/secrets/   || echo secret ldap key doesnt exist\n")
    expect_command("su - pe-postgres -s /bin/bash -c   \"/opt/puppetlabs/server/bin/psql      --tuples-only      -d 'pe-puppetdb'      -c 'DROP SCHEMA IF EXISTS pglogical CASCADE;'\"\n").be_called_times(2)
    expect_command("su - pe-postgres -s /bin/bash -c   \"/opt/puppetlabs/server/bin/psql      -d 'pe-puppetdb'      -c 'DROP SCHEMA public CASCADE; CREATE SCHEMA public; ALTER SCHEMA public OWNER TO pg_database_owner; GRANT USAGE ON SCHEMA public TO PUBLIC;'\"\n")
    expect_command('su - pe-postgres -s /bin/bash -c   "/opt/puppetlabs/server/bin/psql      -d \'pe-puppetdb\'      -c \'ALTER USER \\"pe-puppetdb\\" WITH SUPERUSER;\'"' + "\n")
    expect_command('/opt/puppetlabs/server/bin/pg_restore   -j 4   -d "sslmode=verify-ca       host=postgres       sslcert=/etc/puppetlabs/puppetdb/ssl/primary.cert.pem       sslkey=/etc/puppetlabs/puppetdb/ssl/primary.private_key.pem       sslrootcert=/etc/puppetlabs/puppet/ssl/certs/ca.pem       dbname=pe-puppetdb       user=pe-puppetdb"   -Fd /input/file/puppetdb/pe-puppetdb.dump.d' + "\n")
    expect_command('su - pe-postgres -s /bin/bash -c   "/opt/puppetlabs/server/bin/psql      -d \'pe-puppetdb\'      -c \'ALTER USER \\"pe-puppetdb\\" WITH NOSUPERUSER;\'"' + "\n")
    expect_command('su - pe-postgres -s /bin/bash -c   "/opt/puppetlabs/server/bin/psql      -d \'pe-puppetdb\'      -c \'DROP EXTENSION IF EXISTS pglogical CASCADE;\'"' + "\n")
    expect_command("/opt/puppetlabs/bin/puppet-infrastructure configure --no-recover\n")

    expect(run_plan('peadm::restore', recovery_params)).to be_ok
  end

  # PE-44867 regression guard: pg_database_owner does not exist before
  # PostgreSQL 14, so the owner/USAGE re-grant must be skipped on older PE
  # targets (where CREATE SCHEMA public still auto-grants USAGE anyway).
  context 'against a PostgreSQL < 14 target' do
    let(:psql_version) { '11' }

    it 'recreates public without the owner/USAGE re-grant', valid_cluster: true do
      expect_out_message.with_params('# Restoring database pe-puppetdb')
      expect_out_message.with_params('# Restoring ca, certs, code and config for recovery')

      # No allow_any_command: every command is enumerated, so emitting the
      # pg_database_owner variant here (instead of the plain DROP/CREATE below)
      # would surface as an unexpected command and fail the test.
      expect_command("umask 0077   && cd /input   && tar -xzf /input/file.tar.gz\n")
      expect_command("/opt/puppetlabs/bin/puppet-backup restore   --scope=certs,code,config   --tempdir=/input/file   --force   /input/file/recovery/pe_backup-*tgz\n")
      expect_command("systemctl stop pe-console-services pe-nginx pxp-agent pe-puppetserver                pe-orchestration-services puppet pe-puppetdb\n")
      expect_command("test -f /input/file/rbac/secrets/keys.json   && cp -rp /input/file/rbac/secrets/keys.json /etc/puppetlabs/console-services/conf.d/secrets/   || echo secret ldap key doesnt exist\n")
      expect_command("su - pe-postgres -s /bin/bash -c   \"/opt/puppetlabs/server/bin/psql      --tuples-only      -d 'pe-puppetdb'      -c 'DROP SCHEMA IF EXISTS pglogical CASCADE;'\"\n").be_called_times(2)
      # PostgreSQL < 14: plain DROP/CREATE, with no ALTER OWNER / GRANT USAGE.
      expect_command("su - pe-postgres -s /bin/bash -c   \"/opt/puppetlabs/server/bin/psql      -d 'pe-puppetdb'      -c 'DROP SCHEMA public CASCADE; CREATE SCHEMA public;'\"\n")
      expect_command('su - pe-postgres -s /bin/bash -c   "/opt/puppetlabs/server/bin/psql      -d \'pe-puppetdb\'      -c \'ALTER USER \\"pe-puppetdb\\" WITH SUPERUSER;\'"' + "\n")
      expect_command('/opt/puppetlabs/server/bin/pg_restore   -j 4   -d "sslmode=verify-ca       host=postgres       sslcert=/etc/puppetlabs/puppetdb/ssl/primary.cert.pem       sslkey=/etc/puppetlabs/puppetdb/ssl/primary.private_key.pem       sslrootcert=/etc/puppetlabs/puppet/ssl/certs/ca.pem       dbname=pe-puppetdb       user=pe-puppetdb"   -Fd /input/file/puppetdb/pe-puppetdb.dump.d' + "\n")
      expect_command('su - pe-postgres -s /bin/bash -c   "/opt/puppetlabs/server/bin/psql      -d \'pe-puppetdb\'      -c \'ALTER USER \\"pe-puppetdb\\" WITH NOSUPERUSER;\'"' + "\n")
      expect_command('su - pe-postgres -s /bin/bash -c   "/opt/puppetlabs/server/bin/psql      -d \'pe-puppetdb\'      -c \'DROP EXTENSION IF EXISTS pglogical CASCADE;\'"' + "\n")
      expect_command("/opt/puppetlabs/bin/puppet-infrastructure configure --no-recover\n")

      expect(run_plan('peadm::restore', recovery_params)).to be_ok
    end
  end

  it 'runs with default recovery', valid_cluster: true do
    allow_any_command

    expect_out_message.with_params('# Restoring database pe-puppetdb')
    expect_out_message.with_params('# Restoring ca, certs, code and config for recovery')

    expect(run_plan('peadm::restore', { 'targets' => 'primary', 'input_file' => backup_tarball })).to be_ok
  end

  it 'runs with recovery-db params', valid_cluster: true do
    allow_any_command

    expect_out_message.with_params('# Restoring primary database for recovery')
    expect_out_message.with_params('# Restoring database pe-puppetdb')

    # restore.pp ~365-367: recovery-db is the only restore_type that runs an
    # extra puppet_runonce against the puppetdb postgresql targets (in
    # addition to the unconditional one against $primary_target at ~363).
    # Deleting that `if $restore_type == 'recovery-db'` block, or the task
    # call inside it, would leave this expectation unmet.
    expect_task('peadm::puppet_runonce').with_targets(['postgres'])

    expect(run_plan('peadm::restore', recovery_db_params)).to be_ok
  end

  it 'runs with classifier-only params', valid_cluster: true do
    allow_any_command

    expect_task('peadm::restore_classification').with_params({
                                                               'classification_file' => "#{backup_dir}/classifier/classification_backup.json"
                                                             })

    expect(run_plan('peadm::restore', classifier_only_params)).to be_ok
  end

  it 'runs with recovery params, no valid cluster', valid_cluster: false do
    allow_any_command

    # simulate a failure to get the cluster configuration
    expect_task('peadm::get_peadm_config').always_return({})
    expect_out_message.with_params('Failed to get cluster configuration, loading from backup...')

    # download mocked to return the path to the file fixtures/peadm_config.json
    expect_download("#{backup_dir}/peadm/peadm_config.json").return do |targets, _source, _destination, _params|
      results = targets.map do |target|
        Bolt::Result.new(target, value: { 'path' => File.expand_path(File.join(fixtures, 'peadm_config.json')) })
      end

      Bolt::ResultSet.new(results)
    end
    expect(run_plan('peadm::restore', recovery_params)).to be_ok
  end

  # Cluster-error guard (restore.pp ~52-55): if peadm::get_peadm_config (or the
  # peadm_config.json fallback) reports an 'error' key, the plan must abort via
  # fail_plan() immediately, before any restore action is attempted. If this
  # guard were deleted or inverted, the plan would fall through to
  # peadm::assert_supported_architecture() and beyond, eventually hitting an
  # unmocked run_command/run_task (only the initial tar extraction is stubbed
  # here) -- so this example fails either via an unhandled
  # UnexpectedInvocation, or because `result` never becomes a failure.
  context 'when the cluster configuration reports an error' do
    let(:cluster) do
      {
        'params' => { 'primary_host' => 'primary', 'primary_postgresql_host' => 'postgres' },
        'error'  => 'could not determine cluster topology',
      }
    end

    it 'fails fast via fail_plan and performs no restore actions', valid_cluster: true, cluster_error: true do
      # Only the tar extraction (which runs before the cluster config is even
      # loaded) is mocked. Anything the plan attempts after the guard would be
      # an unexpected, unmocked call.
      expect_command("umask 0077   && cd /input   && tar -xzf /input/file.tar.gz\n")

      result = run_plan('peadm::restore', recovery_params)

      expect(result).not_to be_ok
      expect(result.value.kind).to eq('bolt/plan-failure')
      expect(result.value.msg).to eq('could not determine cluster topology')
    end
  end

  context 'restore_type => migration' do
    let(:migration_params) do
      {
        'targets'          => 'primary',
        'input_file'       => backup_tarball,
        'restore_type'     => 'migration',
        # peadm::rbac_token's task metadata requires 'password' to be a
        # String, so a real console_password must be supplied for the
        # migration path (which is the only restore_type that calls it).
        'console_password' => 'Password1',
      }
    end

    # Migration is the only restore_type that exports/imports puppetdb via the
    # puppet-db archive API (restore.pp ~181-189 export, ~327-360 import); the
    # existing recovery/recovery-db tests never exercise either command.
    # Mutation target: dropping the `and $restore_type == 'migration'` guard
    # on either `if`, or reordering the export to run after shutdown instead
    # of before it, would surface here as a missing/extra/misordered command.
    it 'exports puppetdb before shutdown and imports it after a successful rbac token fetch', valid_cluster: true do
      # expect_command on the export/import text alone (as this test used
      # to do) proves both commands ran, but not in what order relative to
      # each other or to the shutdown step -- moving the export after
      # shutdown, or the import before a successful token fetch, would
      # still pass. Record every command/task call into one shared,
      # ordered log instead, and assert relative position.
      call_log = []
      allow_any_command.return do |targets:, command:, **|
        call_log << command
        Bolt::ResultSet.new(targets.map { |target| Bolt::Result.new(target, value: {}) })
      end
      allow_task('peadm::backup_classification')
      allow_task('peadm::transform_classification_groups')
      allow_task('peadm::restore_classification')
      allow_task('peadm::rbac_token').return do |targets:, **|
        call_log << 'rbac_token'
        Bolt::ResultSet.new(targets.map { |target| Bolt::Result.new(target, value: {}) })
      end

      export_command = "/opt/puppetlabs/bin/puppet-db export   --cert=$(/opt/puppetlabs/bin/puppet config print hostcert)   --key=$(/opt/puppetlabs/bin/puppet config print hostprivkey)   /input/file/puppetdb-archive.bin\n"
      import_command = "/opt/puppetlabs/bin/puppet-db import --cert=$(/opt/puppetlabs/bin/puppet config print hostcert) --key=$(/opt/puppetlabs/bin/puppet config print hostprivkey) /input/file/puppetdb-archive.bin\n"

      expect(run_plan('peadm::restore', migration_params)).to be_ok

      expect(call_log).to include(export_command, import_command, 'rbac_token')
      shutdown_index = call_log.index { |c| c.include?('systemctl stop') }
      expect(shutdown_index).not_to be_nil

      expect(call_log.index(export_command)).to be < shutdown_index
      expect(call_log.index('rbac_token')).to be < call_log.index(import_command)
    end

    # restore.pp ~333-352: on a transient rbac_token failure the plan retries
    # up to $rbac_token_max_attempts (5) times, sleeping 15s between attempts
    # via ctrl::sleep, then fail_plan()s with the last error once attempts are
    # exhausted. Mutation target: an off-by-one in the
    # `range(1, $rbac_token_max_attempts)` bound (this test's
    # be_called_times(5) pins the exact retry count), or the loop silently
    # swallowing the failure instead of calling fail_plan (this test's
    # `.not_to be_ok` / message assertions).
    it 'gives up and fails the plan after exhausting rbac_token retries', valid_cluster: true do
      # ctrl::sleep calls Kernel#sleep for real; stub it out so the retry
      # backoff doesn't make this example take ~60 real seconds. There's no
      # single instance to target -- it executes inside Puppet's plan
      # evaluation -- so any_instance_of is the only option here.
      # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(Object).to receive(:sleep)
      # rubocop:enable RSpec/AnyInstance

      allow_any_command
      allow_task('peadm::backup_classification')
      allow_task('peadm::transform_classification_groups')
      allow_task('peadm::restore_classification')
      expect_task('peadm::rbac_token')
        .error_with({ 'msg' => 'rbac-service unavailable', 'kind' => 'bolt/rbac-error' })
        .be_called_times(5)

      result = run_plan('peadm::restore', migration_params)

      expect(result).not_to be_ok
      expect(result.value.kind).to eq('bolt/plan-failure')
      expect(result.value.msg).to eq('Failed to obtain RBAC token after 5 attempts: rbac-service unavailable')
    end
  end

  # XL topology: primary_postgresql_host and replica_postgresql_host are
  # distinct hosts (restore.pp ~79-88). Every other test in this file only
  # sets primary_postgresql_host, so $puppetdb_postgresql_targets always
  # happens to equal [$primary_target] and would never catch a mutation that
  # dropped/short-circuited the replica branch of the ternary. Here both are
  # set, so the puppetdb restore commands must run against both hosts.
  context 'with a primary and a separate replica PostgreSQL host (XL topology)' do
    let(:cluster) do
      {
        'params' => {
          # peadm::assert_supported_architecture only recognizes a separate
          # replica_postgresql_host as part of the "Extra Large with DR"
          # architecture, which also requires replica_host to be set.
          'primary_host'            => 'primary',
          'replica_host'            => 'replica',
          'primary_postgresql_host' => 'postgres',
          'replica_postgresql_host' => 'postgres-replica',
        },
      }
    end

    it 'restores puppetdb against both the primary and replica PostgreSQL hosts', valid_cluster: true do
      allow_any_command
      expect_task('peadm::get_psql_version')
        .with_targets(['postgres', 'postgres-replica'])
        .always_return({ 'version' => psql_version })

      # If $puppetdb_postgresql_targets only ever resolved to the primary
      # host, this command would be issued against ['postgres'] alone and
      # this target-scoped expectation would go unmatched (unmet expectation,
      # not merely a false negative), failing the example.
      expect_command("su - pe-postgres -s /bin/bash -c   \"/opt/puppetlabs/server/bin/psql      --tuples-only      -d 'pe-puppetdb'      -c 'DROP SCHEMA IF EXISTS pglogical CASCADE;'\"\n")
        .with_targets(['postgres', 'postgres-replica'])
        .be_called_times(2)

      expect(run_plan('peadm::restore', recovery_db_params)).to be_ok
    end
  end

  # Custom-restore ca/code/config are three independent `if`s (restore.pp
  # ~143, 155, 166). The existing classifier-only test sets all three false,
  # so none of the three run_command bodies has ever executed in this file.
  # Each of the following isolates exactly one flag and asserts that its
  # run_command fires while the other two's do not, catching a mutation that
  # merges two branches, or drops/inverts one of the three `if` guards.
  context 'custom restore with a single ca/code/config flag set' do
    let(:isolated_restore_flag) do
      ->(flag) do
        {
          'targets'      => 'primary',
          'input_file'   => backup_tarball,
          'restore_type' => 'custom',
          'restore'      => {
            'activity'     => false,
            'ca'           => false,
            'classifier'   => false,
            'code'         => false,
            'config'       => false,
            'orchestrator' => false,
            'puppetdb'     => false,
            'rbac'         => false,
          }.merge(flag => true),
        }
      end
    end
    let(:ca_command) { "/opt/puppetlabs/bin/puppet-backup restore   --scope=certs   --tempdir=/input/file   --force   /input/file/ca/pe_backup-*tgz\n" }
    let(:code_command) { "/opt/puppetlabs/bin/puppet-backup restore   --scope=code   --tempdir=/input/file   --force   /input/file/code/pe_backup-*tgz\n" }
    let(:config_command) { "/opt/puppetlabs/bin/puppet-backup restore   --scope=config   --tempdir=/input/file   --force   /input/file/config/pe_backup-*tgz\n" }

    before(:each) do
      expect_command("umask 0077   && cd /input   && tar -xzf /input/file.tar.gz\n")
      expect_command("systemctl stop pe-console-services pe-nginx pxp-agent pe-puppetserver                pe-orchestration-services puppet pe-puppetdb\n")
      expect_command("test -f /input/file/rbac/secrets/keys.json   && cp -rp /input/file/rbac/secrets/keys.json /etc/puppetlabs/console-services/conf.d/secrets/   || echo secret ldap key doesnt exist\n")
      expect_command("/opt/puppetlabs/bin/puppet-infrastructure configure --no-recover\n")
    end

    it 'restores only ca/certs when recovery_opts.ca is the only flag set', valid_cluster: true do
      expect_command(ca_command)
      expect_command(code_command).not_be_called
      expect_command(config_command).not_be_called

      expect(run_plan('peadm::restore', isolated_restore_flag.call('ca'))).to be_ok
    end

    it 'restores only code when recovery_opts.code is the only flag set', valid_cluster: true do
      expect_command(ca_command).not_be_called
      expect_command(code_command)
      expect_command(config_command).not_be_called

      expect(run_plan('peadm::restore', isolated_restore_flag.call('code'))).to be_ok
    end

    it 'restores only config when recovery_opts.config is the only flag set', valid_cluster: true do
      expect_command(ca_command).not_be_called
      expect_command(code_command).not_be_called
      expect_command(config_command)

      expect(run_plan('peadm::restore', isolated_restore_flag.call('config'))).to be_ok
    end
  end

  # Orchestrator secret-key copy (restore.pp ~206-211) is gated on
  # recovery_opts.orchestrator and has never been exercised: the existing
  # classifier-only test sets orchestrator => false. Mutation target: deleting
  # the `if getvar('recovery_opts.orchestrator')` guard (so secrets are never
  # copied), or breaking the cp source/destination paths.
  context 'custom restore with only the orchestrator flag set' do
    let(:orchestrator_only_params) do
      {
        'targets'      => 'primary',
        'input_file'   => backup_tarball,
        'restore_type' => 'custom',
        'restore'      => {
          'activity'     => false,
          'ca'           => false,
          'classifier'   => false,
          'code'         => false,
          'config'       => false,
          'orchestrator' => true,
          'puppetdb'     => false,
          'rbac'         => false,
        },
      }
    end

    it 'copies orchestrator secret keys into place', valid_cluster: true do
      allow_any_command

      expect_command("cp -rp /input/file/orchestrator/secrets/* /etc/puppetlabs/orchestration-services/conf.d/secrets/ \n")

      expect(run_plan('peadm::restore', orchestrator_only_params)).to be_ok
    end
  end
end
