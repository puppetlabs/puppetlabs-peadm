# frozen_string_literal: true

require 'spec_helper'

# PE-47523: Bolt logs every task's result in bolt-debug.log, so files that
# can hold secrets are read with as_sensitive, and the content stays wrapped
# in Sensitive on the plan side too.
describe 'peadm::read_sensitive_file' do
  include BoltSpec::BoltContext

  around(:each) do |example|
    in_bolt_context do
      example.run
    end
  end

  let(:path) { '/etc/puppetlabs/orchestration-services/conf.d/secrets/keys.json' }

  it 'reads the file with as_sensitive and returns its content as Sensitive' do
    expect_task('peadm::read_file')
      .with_targets('primary')
      .with_params('path' => path, 'as_sensitive' => true)
      .return { |targets:, **| sensitive_read_file_result(targets, 'keys-canary') }

    is_expected.to run.with_params('primary', path).and_return(Puppet::Pops::Types::PSensitiveType::Sensitive.new('keys-canary'))
  end

  it 'returns undef when the file is missing' do
    expect_task('peadm::read_file').return { |targets:, **| sensitive_read_file_result(targets, nil) }

    is_expected.to run.with_params('primary', path).and_return(nil)
  end

  it 'returns undef when the result has no _sensitive key' do
    expect_task('peadm::read_file').always_return({ 'content' => 'plain' })

    is_expected.to run.with_params('primary', path).and_return(nil)
  end
end
