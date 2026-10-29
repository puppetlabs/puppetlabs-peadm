# frozen_string_literal: true

require 'spec_helper'

# PE-47523: a PostgreSQL node's pe.conf can hold whatever the operator gave the
# installer, console_admin_password included, on a cluster that wasn't built by
# PEADM. The plan reads it as Sensitive and never prints it.
describe 'peadm::util::sanitize_pg_pe_conf' do
  # Include the BoltSpec library functions
  include BoltSpec::Plans

  let(:path) { '/etc/puppetlabs/enterprise/conf.d/pe.conf' }
  let(:pe_conf) { { 'console_admin_password' => 'password-canary', 'puppet_enterprise::database_port' => 5432 } }
  let(:messages) { [] }
  let(:uploads) { {} }

  before(:each) do
    # BoltSpec can't hand back what out::message printed, so record it
    allow_out_message
    allow(executor).to receive(:publish_event).and_wrap_original do |original, event|
      messages << event[:message]
      original.call(event)
    end
  end

  # file_content_upload writes the content to a temporary file and uploads that
  def stub_uploads
    allow_any_upload.return do |targets:, source:, destination:, **|
      uploads[targets.map(&:name).first] = { destination: destination, content: File.read(source) }
      Bolt::ResultSet.new(targets.map { |target| Bolt::Result.for_upload(target, source, destination) })
    end
  end

  it 'reads pe.conf as Sensitive, adds the host names, uploads it, and prints no content' do
    stub_uploads
    expect_task('peadm::read_file')
      .with_params('path' => path, 'as_sensitive' => true)
      .be_called_times(2)
      .return { |targets:, **| sensitive_read_file_result(targets, pe_conf.to_json) }

    result = run_plan('peadm::util::sanitize_pg_pe_conf', 'targets' => 'pg1,pg2', 'primary_host' => 'primary')

    expect(result).to be_ok
    expect(uploads.keys).to contain_exactly('pg1', 'pg2')
    uploads.each do |name, upload|
      expect(upload[:destination]).to eq(path)
      expect(JSON.parse(upload[:content])).to eq(
        pe_conf.merge('puppet_enterprise::puppet_master_host' => 'primary',
                      'puppet_enterprise::puppetdb_database_host' => name),
      )
    end
    expect(messages.join("\n")).not_to include('password-canary')
  end

  it 'fails with a clear message, and uploads nothing, when a node has no pe.conf' do
    stub_uploads
    expect_task('peadm::read_file').return { |targets:, **| sensitive_read_file_result(targets, nil) }

    result = run_plan('peadm::util::sanitize_pg_pe_conf', 'targets' => 'pg1', 'primary_host' => 'primary')

    expect(result).not_to be_ok
    expect(result.value.message).to include("No pe.conf at #{path} on pg1")
    expect(uploads).to be_empty
  end
end
