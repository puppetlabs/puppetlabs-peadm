require 'spec_helper'

describe 'peadm::modify_cert_extensions' do
  include BoltSpec::Plans

  describe 'basic functionality' do
    context 'modifying multiple client certificates' do
      let(:params) do
        {
          'targets'      => 'foo,primary,bar',
          'primary_host' => 'primary',
          'add'          => { 'pe_role' => 'puppet/server' },
        }
      end

      it 'runs successfully ' do
        allow_task('peadm::cert_data').always_return({ 'certname' => 'primary' })
        expect_plan('peadm::subplans::modify_cert_extensions').be_called_times(3)

        expect(run_plan('peadm::modify_cert_extensions', params)).to be_ok
      end
    end
  end
end
