require 'spec_helper'

describe 'peadm::add_compiler' do
  include BoltSpec::Plans

  def allow_standard_non_returning_calls
    allow_apply
    allow_any_task
    allow_any_command
  end

  describe 'basic functionality' do
    let(:params) do
      {
        'primary_host' => 'primary',
        'compiler_host' => 'compiler',
        'avail_group_letter' => 'A',
        'primary_postgresql_host' => 'primary_postgresql',
      }
    end

    let(:cfg) do
      {
        'params' => {
          'primary_host' => 'primary'
        },
        'role-letter' => {
          'server' => {
            'A' => 'server_a',
            'B' => 'server_b'
          }
        }
      }
    end
    let(:certdata) { { 'certname' => 'primary', 'extensions' => { '1.3.6.1.4.1.34380.1.1.9813' => 'A' } } }

    it 'runs successfully when no alt-names are specified' do
      allow_standard_non_returning_calls

      expect_task('peadm::get_peadm_config').always_return(cfg)

      # TODO: Due to difficulty mocking get_targets, with_params modifier has been commented out
      expect_plan('peadm::subplans::component_install')
      # .with_params({
      #   'targets'            => 'compiler',
      #   'primary_host'       => 'primary',
      #   'avail_group_letter' => 'A',
      #   'dns_alt_names'      => nil,
      #   'role'               => 'pe_compiler'
      # })

      expect_plan('peadm::util::copy_file').be_called_times(1)
      expect(run_plan('peadm::add_compiler', params)).to be_ok
    end

    context 'with alt-names' do
      let(:params2) do
        params.merge({ 'dns_alt_names' => 'foo,bar' })
      end

      it 'runs successfully when alt-names are specified' do
        allow_standard_non_returning_calls
        expect_task('peadm::get_peadm_config').always_return(cfg)

        # TODO: Due to difficulty mocking get_targets, with_params modifier has been commented out
        expect_plan('peadm::subplans::component_install')
        # .with_params({
        #   'targets'            => 'compiler',
        #   'primary_host'       => 'primary',
        #   'avail_group_letter' => 'A',
        #   'dns_alt_names'      => 'foo,bar',
        #   'role'               => 'pe_compiler'
        # })

        expect_plan('peadm::util::copy_file').be_called_times(1)
        expect(run_plan('peadm::add_compiler', params2)).to be_ok
      end
    end
  end
end
