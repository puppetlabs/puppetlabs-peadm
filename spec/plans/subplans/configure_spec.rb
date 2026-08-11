require 'spec_helper'

describe 'peadm::subplans::configure' do
  include BoltSpec::Plans

  # configure.pp syncs the CA chain and orchestrator/console encryption keys
  # to $replica_target via copy_file -- a DR replica that never receives
  # these can't serve traffic after failover, and syncing from the wrong
  # source_host would copy the wrong (or replica's own stale) content.
  # PlanStub's with_targets can't be used here: it compares its string names
  # against the raw `targets` param, which still holds resolved Bolt::Target
  # objects at that point, so the Set comparison never matches -- confirmed
  # by instrumenting this call locally. Asserting on
  # params['targets'|'source_host'].map(&:name) inside a return block works
  # instead. Shared by both DR specs below since the assertion is identical
  # in each.
  def expect_copy_file_called_for_replica_only!
    expect_plan('peadm::util::copy_file').be_called_times(5).return do |params:, **|
      expect(Array(params['targets']).map(&:name)).to eq(['replica'])
      expect(Array(params['source_host']).map(&:name)).to eq(['primary'])
      Bolt::PlanResult.new({}, 'success')
    end
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
      expect_plan('peadm::util::copy_file').be_called_times(5)
      expect_task('peadm::provision_replica').not_be_called
      expect_task('peadm::code_manager').not_be_called

      expect(run_plan('peadm::subplans::configure', 'primary_host' => 'primary')).to be_ok
    end
  end

  describe 'Standard architecture with DR' do
    it 'provisions the replica against the primary with the legacy workaround and the given token file' do
      allow_standard_calls!

      expect_task('peadm::provision_replica').with_targets(['primary']).return do |targets:, params:, **|
        # PE-42816: `legacy` is a workaround for a provision_replica race and
        # must stay true until that's fixed elsewhere; flipping it (or losing
        # the replica/token_file plumbing) would silently break DR
        # provisioning without failing this test unless asserted here.
        expect(params['replica']).to eq('replica')
        expect(params['token_file']).to eq('/tmp/token')
        expect(params['legacy']).to eq(true)
        Bolt::ResultSet.new(targets.map { |target| Bolt::Result.new(target, value: {}) })
      end

      # Asserting only on provision_replica's targets/params (above) wouldn't
      # catch a refactor that silently drops or empties the copy_file target
      # list, so pin that down too.
      expect_copy_file_called_for_replica_only!

      expect(run_plan('peadm::subplans::configure',
                       'primary_host' => 'primary',
                       'replica_host' => 'replica',
                       'token_file'   => '/tmp/token')).to be_ok
    end
  end

  describe 'Extra Large architecture with DR' do
    it 'still provisions the replica against the primary, not the postgresql hosts' do
      allow_standard_calls!

      # Confirms adding the split-database (XL) parameters doesn't redirect
      # or skip replica provisioning. with_targets(['primary']) alone would
      # already fail this test if a refactor swapped $primary_target for
      # $primary_postgresql_target; the params assertions additionally catch
      # the XL params corrupting replica/legacy on the call that does happen.
      expect_task('peadm::provision_replica').with_targets(['primary']).return do |targets:, params:, **|
        expect(params['replica']).to eq('replica')
        expect(params['legacy']).to eq(true)
        Bolt::ResultSet.new(targets.map { |target| Bolt::Result.new(target, value: {}) })
      end

      # Same rationale as the standard-with-DR case above: the XL split-database
      # params must not redirect or drop the copy_file replica target either.
      expect_copy_file_called_for_replica_only!

      expect(run_plan('peadm::subplans::configure',
                       'primary_host'            => 'primary',
                       'replica_host'            => 'replica',
                       'primary_postgresql_host' => 'primary_postgresql',
                       'replica_postgresql_host' => 'replica_postgresql')).to be_ok
    end
  end
end
