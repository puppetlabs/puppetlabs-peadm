# frozen_string_literal: true

require 'spec_helper'

# peadm::file_content_upload has no conditional branches - it just writes
# `content` to a Tempfile and forwards it to Bolt's upload_file, so the
# only interesting failure modes are plumbing bugs: wrong/dropped
# arguments, content not actually written before upload, or the return
# value getting transformed instead of passed straight through.
#
# Rather than pulling in the full BoltSpec::Plans plan-executor machinery
# (which would require mocking upload_file's own Tempfile/Pathname/
# module_file_id internals, as spec/plans/subplans/install_spec.rb has to
# do), we get the raw function instance via `subject.func` and stub
# call_function directly. This lets us assert exactly what was forwarded to
# upload_file without needing upload_file's own argument types (a single
# Boltlib::TargetSpec) to validate against our splatted target list.
#
# Note: file_content_upload has no `ensure` around file.close/file.unlink,
# so if upload_file raises, the tempfile leaks. That is pre-existing
# behavior, not something these tests assert on or something we changed.
describe 'peadm::file_content_upload' do
  # rubocop:disable RSpec/NamedSubject
  it 'passes destination and a single target through to upload_file unchanged' do
    allow(subject.func).to receive(:call_function)
      .with('upload_file', anything, 'destination/path', 'target1')
      .and_return('single-target-result')

    result = subject.func.file_content_upload('some content', 'destination/path', 'target1')

    # Catches a mutation that reorders destination/targets, or that stops
    # splatting the repeated `targets` param (e.g. passes it as a single
    # array argument instead), either of which would change what upload_file
    # receives for the single-target call site.
    expect(result).to eq('single-target-result')
  end

  it 'passes multiple targets through to upload_file unchanged' do
    allow(subject.func).to receive(:call_function)
      .with('upload_file', anything, 'destination/path', 'target1', 'target2')
      .and_return('multi-target-result')

    result = subject.func.file_content_upload('some content', 'destination/path', 'target1', 'target2')

    # `targets` is a repeated_param, so callers may pass more than one
    # target. Catches a mutation that only forwards the first target (e.g.
    # `targets.first` instead of `*targets`), which would silently drop
    # every target after the first for multi-target callers.
    expect(result).to eq('multi-target-result')
  end

  it 'writes content to the tempfile before calling upload_file' do
    captured_content = nil
    allow(subject.func).to receive(:call_function) do |function_name, tempfile_path, *_rest|
      captured_content = File.read(tempfile_path) if function_name == 'upload_file'
      'irrelevant-result'
    end

    subject.func.file_content_upload('expected payload', 'destination/path', 'target1')

    # Catches a mutation that drops file.write or file.flush before
    # upload_file is called, which would leave the tempfile empty (or
    # buffered but unflushed) at upload time.
    expect(captured_content).to eq('expected payload')
  end

  it 'returns exactly what upload_file returns, without transformation' do
    fake_result = { 'status' => 'success' }
    allow(subject.func).to receive(:call_function)
      .with('upload_file', anything, 'destination/path', 'target1')
      .and_return(fake_result)

    result = subject.func.file_content_upload('some content', 'destination/path', 'target1')

    # Uses object identity (not just value equality) to catch a mutation
    # that wraps, duplicates, or coerces the upload_file result (e.g.
    # `[result]` or `result.to_s`) instead of returning it as-is.
    expect(result).to equal(fake_result)
  end
  # rubocop:enable RSpec/NamedSubject
end
