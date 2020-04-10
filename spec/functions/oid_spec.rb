# frozen_string_literal: true

require 'spec_helper'
# TODO: test the error case, however due to an issue with boltspec
# and functions we cannot do this right now.
# https://github.com/puppetlabs/bolt/issues/1688
describe 'peadm::oid' do
  it { is_expected.to run.with_params('peadm_role').and_return('1.3.6.1.4.1.34380.1.1.9812') }
  it { is_expected.to run.with_params('peadm_availability_group').and_return('1.3.6.1.4.1.34380.1.1.9813') }
  it { is_expected.to run.with_params('pp_application').and_return('1.3.6.1.4.1.34380.1.1.8') }
  it { is_expected.to run.with_params('pp_cluster').and_return('1.3.6.1.4.1.34380.1.1.16') }
  it do
    is_expected.to run.with_params('bogus')
                      .and_raise_error(Puppet::PreformattedError, %r{No peadm OID for bogus})
  end
end
