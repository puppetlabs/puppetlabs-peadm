# frozen_string_literal: true

require 'spec_helper'

describe 'peadm::fail_on_transport' do
  include BoltSpec::BoltContext

  around :each do |example|
    in_bolt_context do
      example.run
    end
  end

  # NOTE: If https://github.com/puppetlabs/bolt/issues/3184
  #       is fixed, this will start causing a duplicate declaration
  #       error. If that happens, delete this pre_condition.
  let(:pre_condition) do
    'type TargetSpec = Boltlib::TargetSpec'
  end

  let(:nodes) do
    'pcp://target.example'
  end

  # Function testing depends on rspec-puppet magic in the opening describe
  # statement. Re-defining the subject just to give it a different name
  # would require duplicating rspec-puppet code, and that's a far worse sin.
  # rubocop:disable Rspec/NamedSubject
  it 'raises an error when nodes use the specified transport' do
    expect { subject.execute(nodes, 'pcp') }.to raise_error(Puppet::PreformattedError, %r{target\.example uses pcp transport: This is not supported\.})
  end

  it 'raises an error with a custom explanation if one is provided' do
    expect { subject.execute(nodes, 'pcp', 'It would be bad.') }.to raise_error(Puppet::PreformattedError, %r{target\.example uses pcp transport: It would be bad\.})
  end

  it 'raises no error when nodes do not use the specified transport' do
    expect { subject.execute(nodes, 'ssh') }.not_to raise_error
  end
  # rubocop:enable Rspec/NamedSubject
end
