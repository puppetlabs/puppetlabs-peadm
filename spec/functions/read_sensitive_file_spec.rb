# frozen_string_literal: true

require 'spec_helper'

# PE-47523: Bolt logs every task's result in bolt-debug.log, so files that
# can hold secrets are read with as_sensitive, and the content stays wrapped
# in Sensitive on the plan side too. A result the function can't use fails
# rather than reading as a missing file: callers rewrite these files from
# what they read.
describe 'peadm::read_sensitive_file' do
  include BoltSpec::BoltContext

  around(:each) do |example|
    in_bolt_context do
      example.run
    end
  end

  let(:path) { '/etc/puppetlabs/orchestration-services/conf.d/secrets/keys.json' }
  let(:sensitive_content) { Puppet::Pops::Types::PSensitiveType::Sensitive.new('keys-canary') }

  it 'reads the file with as_sensitive and returns its content as Sensitive' do
    expect_task('peadm::read_file')
      .with_targets('primary')
      .with_params('path' => path, 'as_sensitive' => true)
      .return do |targets:, **|
        result = sensitive_read_file_result(targets, 'keys-canary')
        # What Bolt logs at INFO for the result
        expect(result.to_json).not_to include('keys-canary')
        result
      end

    is_expected.to run.with_params('primary', path).and_return(sensitive_content)
  end

  it 'returns undef when the file is missing' do
    expect_task('peadm::read_file').return { |targets:, **| sensitive_read_file_result(targets, nil) }

    is_expected.to run.with_params('primary', path).and_return(nil)
  end

  # Bolt's pcp (Orchestrator) transport doesn't wrap _sensitive when it
  # builds the result.
  it 'accepts an unwrapped _sensitive, as the pcp transport returns it' do
    expect_task('peadm::read_file').always_return({ '_sensitive' => { 'content' => 'keys-canary' } })

    is_expected.to run.with_params('primary', path).and_return(sensitive_content)
  end

  # Over pcp the task comes from the primary's code, which can hold a
  # read_file from before as_sensitive.
  it 'accepts the plain content an older read_file returns' do
    expect_task('peadm::read_file').always_return({ 'content' => 'keys-canary' })

    is_expected.to run.with_params('primary', path).and_return(sensitive_content)
  end

  # A read that failed (Python can't decode the file, say) fails the task
  it 'fails when the read itself fails' do
    expect_task('peadm::read_file').error_with('msg' => 'The task failed with exit code 1', 'kind' => 'puppetlabs.tasks/task-error')

    # rubocop:disable RSpec/NamedSubject
    expect { subject.execute('primary', path) }.to raise_error(Puppet::Error, %r{peadm::read_file.*failed})
    # rubocop:enable RSpec/NamedSubject
  end

  it 'fails, without echoing the output, when the result holds no content' do
    expect_task('peadm::read_file').always_return({ '_output' => 'unparseable keys-canary' })

    # rubocop:disable RSpec/NamedSubject
    expect { subject.execute('primary', path) }.to raise_error(Puppet::Error) { |error|
      expect(error.message).to include("Could not read #{path} on primary: peadm::read_file returned no content")
      expect(error.message).not_to include('keys-canary')
    }
    # rubocop:enable RSpec/NamedSubject
  end
end
