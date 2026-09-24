# frozen_string_literal: true

require 'spec_helper'
require 'puppet/datatypes/impl/error'

# The happy path (recovering a kind from a real result_set) is exercised
# indirectly by spec/plans/demote_ica_compilers_to_proxy_spec.rb's CRL/error
# discrimination tests, which drive it through BoltSpec's `.error_with()` and
# a real Bolt::ResultSet. Reproducing that here would need the same
# boltlib-on-modulepath plan execution context rspec-puppet's bare function
# harness doesn't set up, so this file only covers the guard branches that
# don't depend on it.
describe 'peadm::safe_error_kind' do
  it 'returns undef when details has no result_set key (a non-RunFailure Bolt::Error, e.g. from get_target)' do
    error = Puppet::DataTypes::Error.new('ambiguous target', 'bolt/inventory-error', {})

    is_expected.to run.with_params(error).and_return(nil)
  end

  it 'returns undef when details itself is undef' do
    error = Puppet::DataTypes::Error.new('some error', 'some/kind', nil)

    is_expected.to run.with_params(error).and_return(nil)
  end
end
