# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'

# PE-47523: Bolt logs every task's result in bolt-debug.log at INFO. With
# as_sensitive, read_file returns the content under _sensitive, which Bolt
# wraps in Sensitive and masks in that log. A read that fails fails the task
# instead of printing JSON that Bolt can't parse, which a caller would read as
# a missing file. The script runs for real.
describe 'tasks/read_file.sh' do
  let(:script) { File.expand_path('../../../tasks/read_file.sh', __dir__) }
  let(:workdir) { Dir.mktmpdir }
  let(:file) { File.join(workdir, 'keys.json') }
  let(:missing_file) { { 'content' => nil, 'error' => 'File does not exist or is not readable' } }

  after(:each) do
    FileUtils.remove_entry(workdir)
  end

  # Returns the parsed stdout, after checking the task succeeded
  def read_file(env)
    stdout, stderr, status = Open3.capture3(env, 'bash', script)
    expect(status).to be_success, stderr
    JSON.parse(stdout)
  end

  it 'returns the content under _sensitive when as_sensitive is true' do
    File.write(file, <<~'JSON')
      {"key": "keys-canary \"quoted\" \\ $HOME"}
    JSON

    expect(read_file('PT_path' => file, 'PT_as_sensitive' => 'true')).to eq('_sensitive' => { 'content' => File.read(file) })
  end

  it 'returns a null content under _sensitive, with the error, for a missing file' do
    expect(read_file('PT_path' => File.join(workdir, 'missing'), 'PT_as_sensitive' => 'true'))
      .to eq('_sensitive' => { 'content' => nil }, 'error' => missing_file['error'])
  end

  it 'returns the content at the top level when as_sensitive is not set' do
    File.write(file, "2023.8.10\n")

    expect(read_file('PT_path' => file)).to eq('content' => "2023.8.10\n")
  end

  it 'returns the content at the top level when as_sensitive is false' do
    File.write(file, "2023.8.10\n")

    expect(read_file('PT_path' => file, 'PT_as_sensitive' => 'false')).to eq('content' => "2023.8.10\n")
  end

  it 'returns a null content, with the error, for a missing file' do
    expect(read_file('PT_path' => File.join(workdir, 'missing'))).to eq(missing_file)
  end

  it 'treats a directory as no file' do
    expect(read_file('PT_path' => workdir)).to eq(missing_file)
  end

  # The path is passed to Python as an argument, not as part of its source
  it "reads a file whose path holds a '" do
    quoted = File.join(workdir, "it's.json")
    File.write(quoted, "{}\n")

    expect(read_file('PT_path' => quoted)).to eq('content' => "{}\n")
  end

  it 'treats a file it cannot read as no file', unless: Process.uid.zero? do
    File.write(file, "{}\n")
    File.chmod(0o000, file)

    expect(read_file('PT_path' => file)).to eq(missing_file)
  end

  it 'fails, printing no JSON, when the file is not UTF-8' do
    File.binwrite(file, "caf\xE9\n")

    stdout, _stderr, status = Open3.capture3({ 'PT_path' => file, 'PT_as_sensitive' => 'true' }, 'bash', script)

    expect(status).not_to be_success
    expect(stdout).to be_empty
  end
end
