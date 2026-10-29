# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'

# PE-47523: Bolt logs every task's result in bolt-debug.log at INFO. With
# as_sensitive, read_file returns the content under _sensitive, which Bolt
# wraps in Sensitive and masks in its logs. The script runs for real.
describe 'tasks/read_file.sh' do
  let(:script) { File.expand_path('../../../tasks/read_file.sh', __dir__) }
  let(:workdir) { Dir.mktmpdir }
  let(:file) { File.join(workdir, 'keys.json') }

  after(:each) do
    FileUtils.remove_entry(workdir)
  end

  def read_file(env)
    output, status = Open3.capture2e(env, 'bash', script)
    expect(status).to be_success, output
    JSON.parse(output)
  end

  it 'returns the content under _sensitive when as_sensitive is true' do
    File.write(file, "{\"key\": \"keys-canary \\\"quoted\\\" \\\\ $HOME\"}\n")

    expect(read_file('PT_path' => file, 'PT_as_sensitive' => 'true')).to eq('_sensitive' => { 'content' => File.read(file) })
  end

  it 'returns a null content under _sensitive, with the error, for a missing file' do
    expect(read_file('PT_path' => File.join(workdir, 'missing'), 'PT_as_sensitive' => 'true'))
      .to eq('_sensitive' => { 'content' => nil }, 'error' => 'File does not exist or is not readable')
  end

  it 'returns the content as before when as_sensitive is not set' do
    File.write(file, "2023.8.10\n")

    expect(read_file('PT_path' => file)).to eq('content' => "2023.8.10\n")
  end
end
