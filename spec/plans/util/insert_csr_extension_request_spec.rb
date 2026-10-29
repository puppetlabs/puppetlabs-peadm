require 'spec_helper'

describe 'peadm::util::insert_csr_extension_requests' do
  include BoltSpec::Plans

  describe 'basic functionality' do
    it 'runs successfully against multiple targets' do
      expect_task('peadm::read_file').be_called_times(2)
      expect_task('peadm::mkdir_p_file').be_called_times(2)
      expect(run_plan('peadm::util::insert_csr_extension_requests', 'targets' => 'foo,bar', 'extension_requests' => { 'pe_role' => 'puppet/server' })).to be_ok
    end
  end

  # PE-47523: csr_attributes.yaml can hold custom_attributes such as a
  # challengePassword, and Bolt logs every task's result, so the existing
  # file is read as Sensitive.
  it 'reads the existing csr_attributes.yaml as Sensitive and merges the extension requests into it' do
    existing = "---\ncustom_attributes:\n  1.2.840.113549.1.9.7: challenge-canary\n"
    expect_task('peadm::read_file')
      .with_targets('foo')
      .with_params('path' => '/etc/puppetlabs/puppet/csr_attributes.yaml', 'as_sensitive' => true)
      .return { |targets:, **| sensitive_read_file_result(targets, existing) }
    written = nil
    expect_task('peadm::mkdir_p_file').with_targets('foo').return do |targets:, params:, **|
      written = params['content'].unwrap
      Bolt::ResultSet.new(targets.map { |target| Bolt::Result.new(target, value: {}) })
    end

    expect(run_plan('peadm::util::insert_csr_extension_requests', 'targets' => 'foo', 'extension_requests' => { 'pe_role' => 'puppet/server' })).to be_ok
    expect(YAML.safe_load(written)).to eq(
      'custom_attributes'  => { '1.2.840.113549.1.9.7' => 'challenge-canary' },
      'extension_requests' => { 'pe_role' => 'puppet/server' },
    )
  end
end
