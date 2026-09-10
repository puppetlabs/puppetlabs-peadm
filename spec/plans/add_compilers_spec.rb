require 'spec_helper'

describe 'peadm::add_compilers' do
  include BoltSpec::Plans

  def allow_standard_non_returning_calls
    allow_apply
    allow_any_command
    execute_no_plan
    allow_out_message
  end

  describe 'basic functionality' do
    let(:params) do
      {
        'primary_host' => 'primary',
        'compiler_hosts' => 'compiler',
      }
    end

    let(:params_with_avail_group_b) do
      params.merge({ 'avail_group_letter' => 'B' })
    end

    let(:params_with_primary_postgresql_host) do
      params.merge({ 'primary_postgresql_host' => 'custom_postgresql' })
    end

    let(:cfg) do
      {
        'params' => {
          'primary_host' => 'primary',
          'replica_host' => nil,
          'primary_postgresql_host' => nil,
          'replica_postgresql_host' => nil
        },
        'role-letter' => {
          'server' => {
            'A' => 'server_a',
            'B' => nil
          },
          'postgresql': {
            'A' => nil,
            'B' => nil
          }
        }
      }
    end

    let(:pe_rule_check) do
      {
        'updated' => 'true',
      'message' => 'a message'
      }
    end

    it 'runs successfully when no alt-names are specified' do
      allow_standard_non_returning_calls

      expect_task('peadm::get_peadm_config').always_return(cfg)
      expect_task('peadm::check_pe_master_rules').always_return(pe_rule_check)
      expect_task('peadm::get_psql_version').with_targets(['server_a'])

      expect_plan('peadm::subplans::component_install')
      expect_plan('peadm::util::copy_file').be_called_times(1)
      expect_task('peadm::puppet_runonce').with_targets(['compiler'])
      expect_task('peadm::puppet_runonce').with_targets(['server_a'])
      expect(run_plan('peadm::add_compilers', params)).to be_ok
    end

    it 'handles different avail_group_letter values' do
      allow_standard_non_returning_calls
      cfg['role-letter']['server']['B'] = 'server_b'

      expect_task('peadm::get_peadm_config').always_return(cfg)
      expect_task('peadm::check_pe_master_rules').always_return(pe_rule_check)
      expect_task('peadm::get_psql_version').with_targets(['server_b'])

      expect_plan('peadm::subplans::component_install')
      expect_plan('peadm::util::copy_file').be_called_times(1)
      expect_task('peadm::puppet_runonce').with_targets(['compiler'])
      expect_task('peadm::puppet_runonce').with_targets(['server_a'])
      expect_task('peadm::puppet_runonce').with_targets(['server_b'])
      expect(run_plan('peadm::add_compilers', params_with_avail_group_b)).to be_ok
    end

    it 'handles specified primary_postgresql_host' do
      allow_standard_non_returning_calls

      expect_task('peadm::get_peadm_config').always_return(cfg)
      expect_task('peadm::check_pe_master_rules').always_return(pe_rule_check)
      expect_task('peadm::get_psql_version').with_targets(['custom_postgresql'])

      expect_plan('peadm::subplans::component_install')
      expect_plan('peadm::util::copy_file').be_called_times(1)
      expect_task('peadm::puppet_runonce').with_targets(['compiler'])
      expect_task('peadm::puppet_runonce').with_targets(['custom_postgresql'])
      expect(run_plan('peadm::add_compilers', params_with_primary_postgresql_host)).to be_ok
    end

    it 'handles external postgresql host group A' do
      allow_standard_non_returning_calls
      cfg['params']['primary_postgresql_host'] = 'external_postgresql'
      cfg['params']['replica_postgresql_host'] = 'external_postgresql'

      expect_task('peadm::get_peadm_config').always_return(cfg)
      expect_task('peadm::check_pe_master_rules').always_return(pe_rule_check)
      expect_task('peadm::get_psql_version').with_targets(['external_postgresql'])

      expect_plan('peadm::subplans::component_install')
      expect_plan('peadm::util::copy_file').be_called_times(1)
      expect_task('peadm::puppet_runonce').with_targets(['compiler'])
      expect_task('peadm::puppet_runonce').with_targets(['external_postgresql'])
      expect(run_plan('peadm::add_compilers', params)).to be_ok
    end

    it 'handles external postgresql host group A with replica' do
      allow_standard_non_returning_calls
      cfg['params']['primary_postgresql_host'] = 'external_postgresql'
      cfg['role-letter']['server']['B'] = 'replica'

      expect_task('peadm::get_peadm_config').always_return(cfg)
      expect_task('peadm::check_pe_master_rules').always_return(pe_rule_check)
      expect_task('peadm::get_psql_version').with_targets(['external_postgresql'])

      expect_plan('peadm::subplans::component_install')
      expect_plan('peadm::util::copy_file').be_called_times(1)
      expect_task('peadm::puppet_runonce').with_targets(['compiler'])
      expect_task('peadm::puppet_runonce').with_targets(['external_postgresql'])
      expect_task('peadm::puppet_runonce').with_targets(['replica'])
      expect(run_plan('peadm::add_compilers', params)).to be_ok
    end

    it 'handles external postgresql host group B' do
      allow_standard_non_returning_calls
      cfg['params']['replica_postgresql_host'] = 'replica_external_postgresql'

      expect_task('peadm::get_peadm_config').always_return(cfg)
      expect_task('peadm::check_pe_master_rules').always_return(pe_rule_check)
      expect_task('peadm::get_psql_version').with_targets(['replica_external_postgresql'])

      expect_plan('peadm::subplans::component_install')
      expect_plan('peadm::util::copy_file').be_called_times(1)
      expect_task('peadm::puppet_runonce').with_targets(['compiler'])
      expect_task('peadm::puppet_runonce').with_targets(['replica_external_postgresql'])
      expect_task('peadm::puppet_runonce').with_targets(['server_a'])
      expect(run_plan('peadm::add_compilers', params_with_avail_group_b)).to be_ok
    end
  end
end
