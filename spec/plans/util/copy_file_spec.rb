# frozen_string_literal: true

require 'spec_helper'

# PE-47523: copy_file copies the orchestrator's keys.json and
# orchestrator-encryption-keys.json and console-services' keys.json to the
# replica. Bolt logs both the read's result and the write's arguments, so the
# content is read as Sensitive and written through mkdir_p_file's sensitive
# content parameter.
describe 'peadm::util::copy_file' do
  include BoltSpec::Plans

  let(:path) { '/etc/puppetlabs/console-services/conf.d/secrets/keys.json' }

  before(:each) do
    allow_out_message
  end

  it 'reads the file from the source as Sensitive and writes it to the targets' do
    expect_task('peadm::read_file')
      .with_targets('primary')
      .with_params('path' => path, 'as_sensitive' => true)
      .return { |targets:, **| sensitive_read_file_result(targets, 'keys-canary') }
    expect_task('peadm::mkdir_p_file').with_targets('replica').return do |targets:, params:, **|
      expect(params['path']).to eq(path)
      expect(params['content']).to be_a(Puppet::Pops::Types::PSensitiveType::Sensitive)
      expect(params['content'].unwrap).to eq('keys-canary')
      ok_results(targets)
    end

    expect(run_plan('peadm::util::copy_file', 'targets' => 'replica', 'source_host' => 'primary', 'path' => path)).to be_ok
  end

  it 'skips the write when the source has no such file' do
    expect_task('peadm::read_file').return { |targets:, **| sensitive_read_file_result(targets, nil) }
    expect_task('peadm::mkdir_p_file').not_be_called
    expect_out_message.with_params("Skipping file copy: #{path} on primary had no content")

    expect(run_plan('peadm::util::copy_file', 'targets' => 'replica', 'source_host' => 'primary', 'path' => path)).to be_ok
  end
end
