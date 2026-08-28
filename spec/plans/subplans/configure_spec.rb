require 'spec_helper'

describe 'peadm::subplans::configure' do
  include BoltSpec::Plans

  # configure.pp syncs hiera.yaml plus the CA chain and orchestrator/console
  # encryption keys to $replica_target via copy_file -- a DR replica that
  # never receives these can't serve traffic after failover, and syncing
  # from the wrong source_host (or the same file 5 times instead of the 5
  # distinct files, see synced_replica_files below) would copy the wrong --
  # or missing -- content. PlanStub's with_targets
  # can't be used here: it compares its string names against the raw
  # `targets` param, which still holds resolved Bolt::Target objects at that
  # point, so the Set comparison never matches -- confirmed by instrumenting
  # this call locally. Asserting on params['targets'|'source_host'].map(&:name)
  # inside a return block works instead. Returns the observed `path` values so
  # callers can assert the full set of synced files. Shared by both DR specs
  # below since the assertion is identical in each.
  def expect_copy_file_called_for_replica_only!
    paths = []
    expect_plan('peadm::util::copy_file').be_called_times(5).return do |params:, **|
      expect(Array(params['targets']).map(&:name)).to eq(['replica'])
      expect(Array(params['source_host']).map(&:name)).to eq(['primary'])
      paths << params['path']
      Bolt::PlanResult.new({}, 'success')
    end
    paths
  end

  # The 5 files configure.pp syncs to a DR replica: the common content plus
  # the 4 replica-specific secrets/certs. Kept in sync with configure.pp's
  # $common_content_source and $replica_content_sources. A method rather than
  # a constant: constant assignment resolves lexically (based on where this
  # code is textually nested -- top-level in a spec file), not by the
  # receiver RSpec's class_exec/instance_eval uses at runtime, so a bare
  # constant here would leak into Object regardless of how RSpec invokes the
  # block.
  def synced_replica_files
    [
      '/etc/puppetlabs/puppet/hiera.yaml',
      '/opt/puppetlabs/server/data/console-services/certs/ad_ca_chain.pem',
      '/etc/puppetlabs/orchestration-services/conf.d/secrets/keys.json',
      '/etc/puppetlabs/orchestration-services/conf.d/secrets/orchestrator-encryption-keys.json',
      '/etc/puppetlabs/console-services/conf.d/secrets/keys.json',
    ]
  end

  # Shared stub setup for every example below: none of them care about the
  # exact apply/task/plan/command calls configure.pp makes along the way,
  # only about the specific expectations each sets up afterward.
  def allow_standard_calls!
    allow_apply
    allow_any_task
    allow_any_plan
    allow_any_command
  end

  # Shared by both DR specs below: asserts provision_replica runs against
  # the primary with the PE-42816 legacy workaround and the given
  # replica/token_file plumbing intact. `with_targets(['primary'])` alone
  # would already fail if a refactor swapped $primary_target for
  # $primary_postgresql_target (relevant for the XL case); the params
  # assertions additionally catch the legacy/replica/token_file values
  # getting corrupted on the call that does happen.
  def expect_provision_replica_called_against_primary!
    expect_task('peadm::provision_replica').with_targets(['primary']).return do |targets:, params:, **|
      expect(params['replica']).to eq('replica')
      expect(params['token_file']).to eq('/tmp/token')
      expect(params['legacy']).to eq(true)
      Bolt::ResultSet.new(targets.map { |target| Bolt::Result.new(target, value: {}) })
    end
  end

  # A minimal, fully-populated Peadm::Ldap_config (a Struct type -- every
  # non-Optional key below is required or Puppet type-checking rejects the
  # plan call before BoltSpec ever gets involved).
  def valid_ldap_config
    {
      'base_dn'                             => 'dc=example,dc=com',
      'connect_timeout'                     => 5,
      'disable_ldap_matching_rule_in_chain' => false,
      'display_name'                        => 'LDAP',
      'group_lookup_attr'                   => 'cn',
      'group_member_attr'                   => 'member',
      'group_name_attr'                     => 'cn',
      'group_object_class'                  => 'group',
      'hostname'                            => 'ldap.example.com',
      'port'                                => 389,
      'search_nested_groups'                => false,
      'ssl'                                 => false,
      'ssl_hostname_validation'             => false,
      'ssl_wildcard_validation'             => false,
      'start_tls'                           => false,
      'user_display_name_attr'              => 'displayName',
      'user_email_attr'                     => 'mail',
      'user_lookup_attr'                    => 'uid',
    }
  end

  # NOTE on $cloud_database_host (configure.pp lines ~42, ~117): it is only
  # ever forwarded into peadm::setup::node_manager inside the apply() block
  # at line ~103. BoltSpec::Plans::MockExecutor#apply short-circuits before
  # any catalog is compiled whenever allow_apply is in effect (confirmed by
  # reading mock_executor.rb: `apply` just raises if @allow_apply is false,
  # otherwise returns a stub ApplyResult -- the class body is never
  # evaluated), so there is no way for a plan-spec test in this file to
  # observe whether cloud_database_host actually reached the class. That
  # parameter is intentionally left untested here; it is already covered at
  # the correct layer by spec/classes/setup/node_manager_spec.rb's
  # 'when cloud_database_host is set' context.

  describe 'Standard architecture without DR' do
    it 'runs successfully' do
      allow_standard_calls!

      # PE-45655: peadm::util::copy_file is a *plan* (run via run_plan), not a
      # task -- expect_task binds to a separate mock registry from
      # expect_plan, so `expect_task(...).not_be_called` here always passed
      # regardless of what copy_file actually did. configure.pp calls it
      # unconditionally (once for the common content, 4x in the
      # $replica_content_sources parallelize loop) even with no replica
      # configured, since $replica_target being empty doesn't skip the
      # run_plan calls -- confirmed by instrumenting this exact scenario
      # locally; see spec/plans/add_replica_spec.rb for the same 5-call shape.
      # Asserting targets is empty (not just the call count) would catch a
      # regression that started populating it from $primary_target or
      # $compiler_targets in this no-replica scenario.
      expect_plan('peadm::util::copy_file').be_called_times(5).return do |params:, **|
        expect(Array(params['targets'])).to be_empty
        Bolt::PlanResult.new({}, 'success')
      end
      expect_task('peadm::provision_replica').not_be_called
      expect_task('peadm::code_manager').not_be_called

      expect(run_plan('peadm::subplans::configure', 'primary_host' => 'primary')).to be_ok
    end
  end

  describe 'Standard architecture with DR' do
    it 'provisions the replica against the primary with the legacy workaround and the given token file' do
      allow_standard_calls!

      # PE-42816: `legacy` is a workaround for a provision_replica race and
      # must stay true until that's fixed elsewhere; flipping it (or losing
      # the replica/token_file plumbing) would silently break DR
      # provisioning without failing this test unless asserted here.
      expect_provision_replica_called_against_primary!

      # Asserting only on provision_replica's targets/params (above) wouldn't
      # catch a refactor that silently drops or empties the copy_file target
      # list, so pin that down too.
      copy_file_paths = expect_copy_file_called_for_replica_only!

      expect(run_plan('peadm::subplans::configure',
                       'primary_host' => 'primary',
                       'replica_host' => 'replica',
                       'token_file'   => '/tmp/token')).to be_ok
      expect(copy_file_paths).to match_array(synced_replica_files)
    end
  end

  describe 'Extra Large architecture with DR' do
    it 'still provisions the replica against the primary, not the postgresql hosts' do
      allow_standard_calls!

      # Confirms adding the split-database (XL) parameters doesn't redirect
      # or skip replica provisioning -- see
      # expect_provision_replica_called_against_primary! above for what's
      # asserted.
      expect_provision_replica_called_against_primary!

      # Same rationale as the standard-with-DR case above: the XL split-database
      # params must not redirect or drop the copy_file replica target either.
      copy_file_paths = expect_copy_file_called_for_replica_only!

      expect(run_plan('peadm::subplans::configure',
                       'primary_host'            => 'primary',
                       'replica_host'            => 'replica',
                       'primary_postgresql_host' => 'primary_postgresql',
                       'replica_postgresql_host' => 'replica_postgresql',
                       'token_file'              => '/tmp/token')).to be_ok
      expect(copy_file_paths).to match_array(synced_replica_files)
    end
  end

  describe 'Large architecture (compilers, no DR)' do
    it 'includes compiler_hosts and legacy_compilers in the common-content copy_file target list, ' \
       'and runs update_pe_master_rules/puppet_runonce against the primary/legacy compiler' do
      allow_standard_calls!

      # configure.pp's copy_file plan is called 5 times total regardless of
      # topology (see 'Standard architecture without DR' above): once for
      # the common content (targets = replica + compiler_targets +
      # legacy_compiler_targets), then 4x for replica-only secrets (targets
      # = replica_target only, empty here since there's no replica). Prior
      # to this test, nothing exercised compiler_hosts/legacy_compilers at
      # all, so a regression that dropped either of them from the
      # flatten_compact() call at configure.pp line ~85 (e.g. a bad merge
      # that only kept $replica_target) would pass every other test in this
      # file silently. Distinguish the common call from the 4 replica-only
      # calls by its `path` param (hiera.yaml is unique to the common call;
      # the replica-only calls use the 4 distinct $replica_content_sources
      # paths) rather than by call order, since parallelize() does not
      # guarantee ordering.
      common_content_targets = nil
      expect_plan('peadm::util::copy_file').be_called_times(5).return do |params:, **|
        if params['path'] == '/etc/puppetlabs/puppet/hiera.yaml'
          common_content_targets = Array(params['targets']).map(&:name)
        else
          expect(Array(params['targets'])).to be_empty
        end
        Bolt::PlanResult.new({}, 'success')
      end

      # configure.pp line ~187: update_pe_master_rules always runs against
      # $primary_host, unconditionally, at the very end of the plan. Only
      # ever exercised incidentally via allow_any_task before this; pin the
      # target down explicitly.
      expect_task('peadm::update_pe_master_rules').with_targets(['primary'])

      # configure.pp line ~156 runs puppet_runonce against the combined
      # target list (primary/postgresql/compiler/legacy/replica); line
      # ~188 runs it again, unconditionally, against $legacy_compiler_targets
      # alone. Both calls share the same task name/mock registry, so a
      # generic allow_task catches the line-156 call (not the concern of
      # this test) while the more specific expect_task below -- added after,
      # so BoltSpec checks it first -- pins down the line-188 call. Without
      # this, a regression that dropped the final legacy-compiler-only
      # puppet_runonce call would pass unnoticed.
      allow_task('peadm::puppet_runonce')
      expect_task('peadm::puppet_runonce').with_targets(['legacy_compiler'])

      expect(run_plan('peadm::subplans::configure',
                       'primary_host'     => 'primary',
                       'compiler_hosts'   => 'compiler',
                       'legacy_compilers' => 'legacy_compiler')).to be_ok
      expect(common_content_targets).to match_array(%w[compiler legacy_compiler])
    end
  end

  describe 'ldap_config' do
    # Prior to this describe block, the entire $ldap_config branch
    # (configure.pp lines ~135-153) was untested: nothing ever set
    # ldap_config, so a regression here -- wrong pe_version, wrong target,
    # or swallowing/hard-failing on error -- could not be caught by any
    # existing test.
    it 'reads the PE version from disk and threads it through to pe_ldap_config along with pe_main and ldap_config' do
      allow_standard_calls!

      expect_task('peadm::read_file')
        .with_params('path' => '/opt/puppetlabs/server/pe_version')
        .always_return({ 'content' => "2023.8.1\n" })

      # Catches: (a) pe_version not being read at all or read from the wrong
      # path, (b) the trailing newline from the file read leaking through
      # unchomped, (c) pe_main/ldap_config getting dropped or corrupted, and
      # (d) the task being run against the wrong target.
      expect_task('peadm::pe_ldap_config').with_targets(['primary']).return do |targets:, params:, **|
        expect(params['pe_main']).to eq('primary')
        expect(params['ldap_config']).to eq(valid_ldap_config)
        expect(params['pe_version']).to eq('2023.8.1')
        Bolt::ResultSet.new(targets.map { |target| Bolt::Result.new(target, value: {}) })
      end

      expect(run_plan('peadm::subplans::configure',
                       'primary_host' => 'primary',
                       'ldap_config'  => valid_ldap_config)).to be_ok
    end

    it 'logs both messages and still succeeds (does not hard-fail) when pe_ldap_config errors' do
      allow_standard_calls!

      expect_task('peadm::read_file')
        .with_params('path' => '/opt/puppetlabs/server/pe_version')
        .always_return({ 'content' => '2023.8.1' })

      expect_task('peadm::pe_ldap_config').with_targets(['primary']).return do |targets:, **|
        Bolt::ResultSet.new(targets.map do |target|
          Bolt::Result.new(target, value: { '_error' => { 'msg' => 'ldap bind failed', 'kind' => 'peadm/ldap-error' } })
        end)
      end

      static_notice = 'There was a problem with the LDAP configuration, configuration must be completed manually.'

      # configure.pp logs two separate out::message calls on LDAP failure:
      # the static notice above, then `$ldap_result.to_data` (dynamic
      # content we can't predict/match exactly here). PublishStub#matches
      # does exact string/data equality with no with_params filter set
      # matching everything, and ActionDouble#process always hands a call to
      # the *most recently added* matching stub (stubs are unshifted, so
      # last-added is checked first) -- so the generic catch-all below must
      # be added FIRST (so it ends up behind) and the exact-text stub SECOND
      # (so it ends up in front and intercepts the static-text call before
      # the generic one can). Getting this order backwards would make the
      # generic stub swallow both calls and the exact-text expectation would
      # never see a call, failing with a false "expected at least one call"
      # error even though configure.pp is behaving correctly.
      expect_out_message.be_called_times(1) # catches the dynamic $ldap_result.to_data call
      expect_out_message.with_params(static_notice) # catches the static notice, exactly once

      # The real assertion: both log lines fire (via the two out::message
      # expectations above) AND the plan is still `ok` -- proving "log and
      # continue" rather than either (a) a silent swallow with no message at
      # all, or (b) an accidental hard failure that surfaces the LDAP error
      # as a plan failure instead of logging it.
      expect(run_plan('peadm::subplans::configure',
                       'primary_host' => 'primary',
                       'ldap_config'  => valid_ldap_config)).to be_ok
    end
  end

  describe 'deploy_environment' do
    # Prior to this describe block, only the negative (deploy_environment
    # unset -> code_manager not called) was proven, and only implicitly, via
    # allow_standard_calls!'s allow_any_task silently accepting the absence
    # of any call. Nothing proved code_manager actually gets invoked, with
    # the right action string, when deploy_environment IS set.
    it 'runs code_manager against the primary with a "deploy <environment>" action when deploy_environment is set' do
      allow_standard_calls!

      expect_task('peadm::code_manager').with_targets(['primary']).return do |targets:, params:, **|
        expect(params['action']).to eq('deploy production')
        Bolt::ResultSet.new(targets.map { |target| Bolt::Result.new(target, value: {}) })
      end

      expect(run_plan('peadm::subplans::configure',
                       'primary_host'       => 'primary',
                       'deploy_environment' => 'production')).to be_ok
    end
  end

  describe 'final_agent_state' do
    # Every other test in this file relies on the 'running' default (agent
    # service started). This is the only test that exercises
    # final_agent_state => 'stopped', so a regression that hard-coded
    # 'start' regardless of $final_agent_state, or broke the running/stopped
    # => start/stop mapping at configure.pp lines ~173-176, would otherwise
    # go uncaught.
    it 'stops the puppet agent service when final_agent_state is "stopped"' do
      allow_standard_calls!

      expect_command('systemctl stop puppet').with_targets(['primary'])

      expect(run_plan('peadm::subplans::configure',
                       'primary_host'      => 'primary',
                       'final_agent_state' => 'stopped')).to be_ok
    end
  end
end
