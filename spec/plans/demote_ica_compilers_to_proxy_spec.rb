require 'spec_helper'

describe 'peadm::demote_ica_compilers_to_proxy' do
  include BoltSpec::Plans

  def allow_standard_non_returning_calls
    allow_any_task
    allow_any_out_message
  end

  let(:base_params) { { 'primary_host' => 'primary', 'quiet_period_seconds' => 0 } }

  describe 'parameter validation' do
    it 'fails when both all and compilers are given' do
      allow_standard_non_returning_calls
      params = base_params.merge('all' => true, 'compilers' => 'compiler-a')

      result = run_plan('peadm::demote_ica_compilers_to_proxy', params)

      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{specify either \$all or \$compilers, not both})
    end

    it 'fails when neither all nor compilers are given' do
      allow_standard_non_returning_calls

      result = run_plan('peadm::demote_ica_compilers_to_proxy', base_params)

      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{specify either \$all => true or a \$compilers target})
    end
  end

  describe 'fleet impact acknowledgement' do
    it 'fails when $all resolves more compilers than batch_size without acknowledgement' do
      allow_standard_non_returning_calls
      expect_task('peadm::list_compiler_icas').always_return(
        'intermediate-cas' => [
          { 'compiler-fqdn' => 'compiler-a', 'state' => 'active' },
          { 'compiler-fqdn' => 'compiler-b', 'state' => 'active' },
        ],
      )

      result = run_plan('peadm::demote_ica_compilers_to_proxy', base_params.merge('all' => true, 'batch_size' => 1))

      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{\$all resolved 2 ICA compilers, more than \$batch_size \(1\)})
    end

    it 'proceeds when acknowledge_fleet_impact is set' do
      allow_standard_non_returning_calls
      expect_task('peadm::list_compiler_icas').always_return(
        'intermediate-cas' => [
          { 'compiler-fqdn' => 'compiler-a', 'state' => 'active' },
          { 'compiler-fqdn' => 'compiler-b', 'state' => 'active' },
        ],
      )
      expect_task('peadm::get_ica_state').always_return('state' => 'active').be_called_times(2)
      expect_task('peadm::drain_ica_compiler').be_called_times(2)
      expect_task('peadm::restore_ca_proxy_bootstrap').be_called_times(2)
      expect_task('peadm::restart_ca_service').be_called_times(2)
      expect_task('peadm::decommission_compiler_ica').be_called_times(2)
      expect_task('peadm::cleanup_ica_key_material').be_called_times(2)

      params = base_params.merge('all' => true, 'batch_size' => 1, 'acknowledge_fleet_impact' => true)
      result = run_plan('peadm::demote_ica_compilers_to_proxy', params)

      expect(result).to be_ok
      expect(result.value['demoted']).to eq(['compiler-a', 'compiler-b'])
    end

    it 'does not require acknowledgement when $all resolves no more compilers than batch_size' do
      allow_standard_non_returning_calls
      expect_task('peadm::list_compiler_icas').always_return(
        'intermediate-cas' => [
          { 'compiler-fqdn' => 'compiler-a', 'state' => 'active' },
          { 'compiler-fqdn' => 'compiler-b', 'state' => 'active' },
        ],
      )
      expect_task('peadm::get_ica_state').always_return('state' => 'active').be_called_times(2)

      params = base_params.merge('all' => true, 'batch_size' => 2)
      result = run_plan('peadm::demote_ica_compilers_to_proxy', params)

      expect(result).to be_ok
      expect(result.value['demoted']).to eq(['compiler-a', 'compiler-b'])
    end
  end

  describe 'preflight' do
    it 'fails with a clear message when list_compiler_icas fails, rather than a raw Bolt failure' do
      allow_standard_non_returning_calls
      expect_task('peadm::list_compiler_icas')
        .error_with('msg' => 'primary unreachable', 'kind' => 'peadm/list_compiler_icas_failed')

      result = run_plan('peadm::demote_ica_compilers_to_proxy', base_params.merge('all' => true))

      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{failed to list compiler ICAs on primary})
    end

    it 'fails with a clear message when get_ica_state fails, rather than a raw Bolt failure' do
      allow_standard_non_returning_calls
      expect_task('peadm::get_ica_state')
        .error_with('msg' => 'primary unreachable', 'kind' => 'peadm/get_ica_state_failed')

      result = run_plan('peadm::demote_ica_compilers_to_proxy', base_params.merge('compilers' => 'compiler-a'))

      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{failed to look up ICA state for compiler-a})
    end

    it 'skips a compiler with no live ICA rather than demoting it' do
      allow_standard_non_returning_calls
      expect_task('peadm::get_ica_state').always_return('state' => 'none')
      expect_task('peadm::drain_ica_compiler').be_called_times(0)

      result = run_plan('peadm::demote_ica_compilers_to_proxy', base_params.merge('compilers' => 'compiler-a'))

      expect(result).to be_ok
      expect(result.value['demoted']).to eq([])
      expect(result.value['skipped']).to eq(['compiler-a'])
    end

    ['revoked', 'decommissioned'].each do |state|
      it "skips a compiler whose ICA is already #{state}" do
        allow_standard_non_returning_calls
        expect_task('peadm::get_ica_state').always_return('state' => state)
        expect_task('peadm::drain_ica_compiler').be_called_times(0)

        result = run_plan('peadm::demote_ica_compilers_to_proxy', base_params.merge('compilers' => 'compiler-a'))

        expect(result).to be_ok
        expect(result.value['demoted']).to eq([])
        expect(result.value['skipped']).to eq(['compiler-a'])
      end
    end

    it 'demotes only the live compiler and skips only the dead one when both are requested together' do
      allow_standard_non_returning_calls
      expect_task('peadm::get_ica_state').with_params('compiler_fqdn' => 'compiler-a').always_return('state' => 'active')
      expect_task('peadm::get_ica_state').with_params('compiler_fqdn' => 'compiler-b').always_return('state' => 'decommissioned')
      expect_task('peadm::drain_ica_compiler').with_params('compiler_fqdn' => 'compiler-a', 'token_file' => nil).be_called_times(1)
      expect_task('peadm::drain_ica_compiler').with_params('compiler_fqdn' => 'compiler-b', 'token_file' => nil).be_called_times(0)

      params = base_params.merge('compilers' => 'compiler-a,compiler-b')
      result = run_plan('peadm::demote_ica_compilers_to_proxy', params)

      expect(result).to be_ok
      expect(result.value['demoted']).to eq(['compiler-a'])
      expect(result.value['skipped']).to eq(['compiler-b'])
    end
  end

  describe 'batch_size default' do
    it 'defaults to 1, so two compilers land in two separate batches (one quiet-period sleep each)' do
      allow_standard_non_returning_calls
      expect_task('peadm::get_ica_state').always_return('state' => 'active').be_called_times(2)
      expect_task('peadm::drain_ica_compiler').be_called_times(2)
      expect_task('peadm::decommission_compiler_ica').be_called_times(2)
      sleep_calls = 0
      allow_any_instance_of(Object).to receive(:sleep) { |_, _period| sleep_calls += 1 } # rubocop:disable RSpec/AnyInstance

      params = { 'primary_host' => 'primary', 'compilers' => 'compiler-a,compiler-b' }
      result = run_plan('peadm::demote_ica_compilers_to_proxy', params)

      expect(result).to be_ok
      expect(result.value['demoted']).to eq(['compiler-a', 'compiler-b'])
      expect(sleep_calls).to eq(2)
    end
  end

  describe 'the default (decommission) path' do
    it 'drains, restores proxy bootstrap, restarts, decommissions, and cleans up key material' do
      allow_standard_non_returning_calls
      expect_task('peadm::get_ica_state').always_return('state' => 'active')
      expect_task('peadm::drain_ica_compiler').with_params('compiler_fqdn' => 'compiler-a', 'token_file' => nil).be_called_times(1)
      expect_task('peadm::restore_ca_proxy_bootstrap').with_params('proxy_target' => 'primary').be_called_times(1)
      expect_task('peadm::restart_ca_service').be_called_times(1)
      expect_task('peadm::decommission_compiler_ica').with_params('compiler_fqdn' => 'compiler-a', 'token_file' => nil).be_called_times(1)
      expect_task('peadm::revoke_compiler_ica').be_called_times(0)
      expect_task('peadm::cleanup_ica_key_material').be_called_times(1)

      result = run_plan('peadm::demote_ica_compilers_to_proxy', base_params.merge('compilers' => 'compiler-a'))

      expect(result).to be_ok
      expect(result.value['demoted']).to eq(['compiler-a'])
    end

    it 'runs cleanup_ica_key_material before decommission/revoke, so a cleanup failure never leaves an unretryable half-demoted compiler' do
      allow_standard_non_returning_calls
      expect_task('peadm::get_ica_state').always_return('state' => 'active')
      expect_task('peadm::cleanup_ica_key_material')
        .error_with('msg' => 'permission denied', 'kind' => 'peadm/cleanup_ica_key_material_failed')
      expect_task('peadm::decommission_compiler_ica').be_called_times(0)
      expect_task('peadm::revoke_compiler_ica').be_called_times(0)

      result = run_plan('peadm::demote_ica_compilers_to_proxy', base_params.merge('compilers' => 'compiler-a'))

      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{Failed batch \(compiler-a\)})
    end

    it 'threads custom proxy_target and token_file through to every task that needs them' do
      allow_standard_non_returning_calls
      expect_task('peadm::get_ica_state').always_return('state' => 'active')
      expect_task('peadm::drain_ica_compiler').with_params('compiler_fqdn' => 'compiler-a', 'token_file' => '/custom/token').be_called_times(1)
      expect_task('peadm::restore_ca_proxy_bootstrap').with_params('proxy_target' => 'https://ica-pool.example.com').be_called_times(1)
      expect_task('peadm::decommission_compiler_ica').with_params('compiler_fqdn' => 'compiler-a', 'token_file' => '/custom/token').be_called_times(1)

      params = base_params.merge(
        'compilers' => 'compiler-a',
        'proxy_target' => 'https://ica-pool.example.com',
        'token_file' => '/custom/token',
      )
      result = run_plan('peadm::demote_ica_compilers_to_proxy', params)

      expect(result).to be_ok
      expect(result.value['demoted']).to eq(['compiler-a'])
    end
  end

  describe 'the $revoke path' do
    it 'calls revoke_compiler_ica instead of decommission_compiler_ica' do
      allow_standard_non_returning_calls
      expect_task('peadm::get_ica_state').always_return('state' => 'draining')
      expect_task('peadm::revoke_compiler_ica').with_params('compiler_fqdn' => 'compiler-a', 'token_file' => nil).be_called_times(1)
      expect_task('peadm::decommission_compiler_ica').be_called_times(0)

      params = base_params.merge('compilers' => 'compiler-a', 'revoke' => true)
      result = run_plan('peadm::demote_ica_compilers_to_proxy', params)

      expect(result).to be_ok
      expect(result.value['demoted']).to eq(['compiler-a'])
    end

    it 'warns precisely when revoke_compiler_ica fails with crl-updated:false, since a re-run would silently skip the now-revoked ICA' do
      allow_standard_non_returning_calls
      expect_task('peadm::get_ica_state').always_return('state' => 'draining')
      expect_task('peadm::revoke_compiler_ica')
        .error_with('msg' => 'Intermediate CA for compiler-a was marked revoked, but the root CRL was not updated', 'kind' => 'peadm/revoke_compiler_ica_crl_not_updated')

      params = base_params.merge('compilers' => 'compiler-a', 'revoke' => true)
      result = run_plan('peadm::demote_ica_compilers_to_proxy', params)

      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{compiler-a's ICA is now marked revoked at the primary})
      expect(result.value.msg).to match(%r{do not rely on a re-run to fix this one})
    end

    it 'does not add the CRL caveat on the default (decommission) path' do
      allow_standard_non_returning_calls
      expect_task('peadm::get_ica_state').always_return('state' => 'active')
      expect_task('peadm::decommission_compiler_ica')
        .error_with('msg' => 'primary unreachable', 'kind' => 'peadm/decommission_compiler_ica_failed')

      result = run_plan('peadm::demote_ica_compilers_to_proxy', base_params.merge('compilers' => 'compiler-a'))

      expect(result).not_to be_ok
      expect(result.value.msg).not_to match(%r{ICA is now marked revoked at the primary})
    end

    it 'does not add the CRL caveat on the $revoke path when the failure is unrelated to revoke_compiler_ica' do
      allow_standard_non_returning_calls
      expect_task('peadm::get_ica_state').always_return('state' => 'active')
      expect_task('peadm::drain_ica_compiler')
        .error_with('msg' => 'no active or draining ICA', 'kind' => 'peadm/drain_ica_compiler_failed')
      expect_task('peadm::revoke_compiler_ica').be_called_times(0)

      params = base_params.merge('compilers' => 'compiler-a', 'revoke' => true)
      result = run_plan('peadm::demote_ica_compilers_to_proxy', params)

      expect(result).not_to be_ok
      expect(result.value.msg).not_to match(%r{ICA is now marked revoked at the primary})
    end

    it 'does not add the CRL caveat on the $revoke path when revoke_compiler_ica fails for a different reason' do
      allow_standard_non_returning_calls
      expect_task('peadm::get_ica_state').always_return('state' => 'draining')
      expect_task('peadm::revoke_compiler_ica')
        .error_with('msg' => 'HTTP 500 - internal error', 'kind' => 'peadm/revoke_compiler_ica_failed')

      params = base_params.merge('compilers' => 'compiler-a', 'revoke' => true)
      result = run_plan('peadm::demote_ica_compilers_to_proxy', params)

      expect(result).not_to be_ok
      expect(result.value.msg).not_to match(%r{ICA is now marked revoked at the primary})
    end
  end

  describe 'a compiler that is already draining' do
    it 'skips the redundant drain call, since the drain endpoint 409s on anything but an active ICA' do
      allow_standard_non_returning_calls
      expect_task('peadm::get_ica_state').always_return('state' => 'draining')
      expect_task('peadm::drain_ica_compiler').be_called_times(0)
      expect_task('peadm::decommission_compiler_ica').with_params('compiler_fqdn' => 'compiler-a', 'token_file' => nil).be_called_times(1)

      result = run_plan('peadm::demote_ica_compilers_to_proxy', base_params.merge('compilers' => 'compiler-a'))

      expect(result).to be_ok
      expect(result.value['demoted']).to eq(['compiler-a'])
    end

    it 'skips the drain call only for the already-draining member of a mixed batch, not the active one, and still waits out the quiet period' do
      allow_standard_non_returning_calls
      expect_task('peadm::get_ica_state').with_params('compiler_fqdn' => 'compiler-a').always_return('state' => 'active')
      expect_task('peadm::get_ica_state').with_params('compiler_fqdn' => 'compiler-b').always_return('state' => 'draining')
      expect_task('peadm::drain_ica_compiler').with_params('compiler_fqdn' => 'compiler-a', 'token_file' => nil).be_called_times(1)
      expect_task('peadm::drain_ica_compiler').with_params('compiler_fqdn' => 'compiler-b', 'token_file' => nil).be_called_times(0)
      expect_task('peadm::decommission_compiler_ica').be_called_times(2)
      sleep_calls = 0
      allow_any_instance_of(Object).to receive(:sleep) { |_, _period| sleep_calls += 1 } # rubocop:disable RSpec/AnyInstance

      params = base_params.merge('compilers' => 'compiler-a,compiler-b', 'batch_size' => 2, 'quiet_period_seconds' => 5)
      result = run_plan('peadm::demote_ica_compilers_to_proxy', params)

      expect(result).to be_ok
      expect(result.value['demoted']).to eq(['compiler-a', 'compiler-b'])
      expect(sleep_calls).to eq(1)
    end
  end

  describe 'batch sequencing and failure reporting' do
    it 'leaves a later batch untouched when an earlier batch fails, and names both in the failure message' do
      allow_standard_non_returning_calls
      expect_task('peadm::get_ica_state').always_return('state' => 'active').be_called_times(3)
      expect_task('peadm::drain_ica_compiler')
        .with_params('compiler_fqdn' => 'compiler-b', 'token_file' => nil)
        .error_with('msg' => 'no active or draining ICA', 'kind' => 'peadm/drain_ica_compiler_failed')
      expect_task('peadm::drain_ica_compiler').with_params('compiler_fqdn' => 'compiler-a', 'token_file' => nil)
      expect_task('peadm::drain_ica_compiler').with_params('compiler_fqdn' => 'compiler-c', 'token_file' => nil).be_called_times(0)
      expect_task('peadm::restore_ca_proxy_bootstrap').with_params('proxy_target' => 'primary').be_called_times(1)
      expect_task('peadm::decommission_compiler_ica').with_params('compiler_fqdn' => 'compiler-a', 'token_file' => nil).be_called_times(1)
      expect_task('peadm::decommission_compiler_ica').with_params('compiler_fqdn' => 'compiler-c', 'token_file' => nil).be_called_times(0)

      params = base_params.merge('compilers' => 'compiler-a,compiler-b,compiler-c', 'batch_size' => 1)
      result = run_plan('peadm::demote_ica_compilers_to_proxy', params)

      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{Demoted before the failure: compiler-a})
      expect(result.value.msg).to match(%r{Failed batch \(compiler-b\)})
      expect(result.value.msg).to match(%r{Not attempted: compiler-c})
    end

    it 'counts a compiler that fully completes as demoted even when a later compiler in the same batch fails' do
      allow_standard_non_returning_calls
      expect_task('peadm::get_ica_state').always_return('state' => 'active').be_called_times(3)
      expect_task('peadm::drain_ica_compiler').be_called_times(3)
      expect_task('peadm::restore_ca_proxy_bootstrap').with_params('proxy_target' => 'primary').be_called_times(2)
      expect_task('peadm::restart_ca_service')
        .with_targets('compiler-b')
        .error_with('msg' => 'pe-puppetserver did not become active', 'kind' => 'peadm/restart_ca_service_failed')
      expect_task('peadm::restart_ca_service').with_targets('compiler-a')
      expect_task('peadm::restart_ca_service').with_targets('compiler-c').be_called_times(0)
      expect_task('peadm::decommission_compiler_ica').with_params('compiler_fqdn' => 'compiler-a', 'token_file' => nil).be_called_times(1)
      expect_task('peadm::decommission_compiler_ica').with_params('compiler_fqdn' => 'compiler-c', 'token_file' => nil).be_called_times(0)

      params = base_params.merge('compilers' => 'compiler-a,compiler-b,compiler-c', 'batch_size' => 3)
      result = run_plan('peadm::demote_ica_compilers_to_proxy', params)

      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{Demoted before the failure: compiler-a})
      expect(result.value.msg).to match(%r{Failed batch \(compiler-b\)})
      # compiler-b itself was also drained (the whole batch's drain succeeds
      # before the finish phase starts), so it belongs in this bucket too,
      # not just named as the failure.
      drained_but_not_finished = result.value.msg[%r{Drained but not finished[^:]*: ([^.]+)\.}, 1]
      expect(drained_but_not_finished.split(', ')).to contain_exactly('compiler-b', 'compiler-c')
      expect(result.value.msg).to match(%r{Not attempted: none})
    end

    it 'reports a compiler drained before a later drain in the same batch fails as drained-but-not-finished, not demoted or untouched' do
      allow_standard_non_returning_calls
      expect_task('peadm::get_ica_state').always_return('state' => 'active').be_called_times(3)
      expect_task('peadm::drain_ica_compiler').with_params('compiler_fqdn' => 'compiler-a', 'token_file' => nil)
      expect_task('peadm::drain_ica_compiler')
        .with_params('compiler_fqdn' => 'compiler-b', 'token_file' => nil)
        .error_with('msg' => 'no active or draining ICA', 'kind' => 'peadm/drain_ica_compiler_failed')
      expect_task('peadm::drain_ica_compiler').with_params('compiler_fqdn' => 'compiler-c', 'token_file' => nil).be_called_times(0)
      expect_task('peadm::restore_ca_proxy_bootstrap').be_called_times(0)

      params = base_params.merge('compilers' => 'compiler-a,compiler-b,compiler-c', 'batch_size' => 3)
      result = run_plan('peadm::demote_ica_compilers_to_proxy', params)

      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{Demoted before the failure: none})
      expect(result.value.msg).to match(%r{Failed batch \(compiler-b\)})
      expect(result.value.msg).to match(%r{Drained but not finished.*compiler-a})
      expect(result.value.msg).to match(%r{Not attempted: compiler-c})
    end
  end

  describe 'quiet period timing' do
    it 'sleeps once for a whole batch, not once per compiler in that batch' do
      allow_standard_non_returning_calls
      expect_task('peadm::get_ica_state').always_return('state' => 'active').be_called_times(3)
      sleep_calls = 0
      allow_any_instance_of(Object).to receive(:sleep) { |_, _period| sleep_calls += 1 } # rubocop:disable RSpec/AnyInstance

      params = { 'primary_host' => 'primary', 'compilers' => 'compiler-a,compiler-b,compiler-c', 'batch_size' => 3, 'quiet_period_seconds' => 5 }
      result = run_plan('peadm::demote_ica_compilers_to_proxy', params)

      expect(result).to be_ok
      expect(sleep_calls).to eq(1)
    end

    it 'sleeps once per batch when compilers span multiple batches' do
      allow_standard_non_returning_calls
      expect_task('peadm::get_ica_state').always_return('state' => 'active').be_called_times(3)
      sleep_calls = 0
      allow_any_instance_of(Object).to receive(:sleep) { |_, _period| sleep_calls += 1 } # rubocop:disable RSpec/AnyInstance

      params = { 'primary_host' => 'primary', 'compilers' => 'compiler-a,compiler-b,compiler-c', 'batch_size' => 1, 'quiet_period_seconds' => 5 }
      result = run_plan('peadm::demote_ica_compilers_to_proxy', params)

      expect(result).to be_ok
      expect(sleep_calls).to eq(3)
    end

    it 'skips the wait entirely when every compiler in the batch was already draining' do
      allow_standard_non_returning_calls
      expect_task('peadm::get_ica_state').always_return('state' => 'draining')
      expect_task('peadm::drain_ica_compiler').be_called_times(0)
      sleep_calls = 0
      allow_any_instance_of(Object).to receive(:sleep) { |_, _period| sleep_calls += 1 } # rubocop:disable RSpec/AnyInstance

      params = base_params.merge('compilers' => 'compiler-a', 'quiet_period_seconds' => 5)
      result = run_plan('peadm::demote_ica_compilers_to_proxy', params)

      expect(result).to be_ok
      expect(sleep_calls).to eq(0)
    end
  end
end
