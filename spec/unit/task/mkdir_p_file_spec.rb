# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'

# PE-47523: mkdir_p_file takes its parameters as JSON on stdin. With
# environment input, Bolt passes them on the remote command line
# (`env PT_content=...`), where sudo logs them and ps shows them, so the
# content (pe.conf, the r10k key, the license) must not depend on PT_*
# variables. The script runs for real, with only stdin input.
describe 'tasks/mkdir_p_file.sh' do
  let(:script) { File.expand_path('../../../tasks/mkdir_p_file.sh', __dir__) }
  let(:workdir) { Dir.mktmpdir }

  after(:each) do
    FileUtils.remove_entry(workdir)
  end

  # Bolt adds _task to stdin input.
  def run_task(params)
    Open3.capture2e('bash', script, stdin_data: params.merge('_task' => 'peadm::mkdir_p_file').to_json)
  end

  it 'writes the content verbatim, plus a newline, creating missing directories' do
    path = File.join(workdir, 'conf.d', 'pe.conf')
    content = "{\n  \"console_admin_password\": \"$(id) `id` $HOME \\\\ \\\"q\\\" é\"\n}"

    output, status = run_task('path' => path, 'content' => content)

    expect(status).to be_success, output
    expect(File.read(path, encoding: 'UTF-8')).to eq("#{content}\n")
  end

  it 'replaces the content of an existing file' do
    path = File.join(workdir, 'license.key')
    File.write(path, "old content that is longer than the new one\n")

    output, status = run_task('path' => path, 'content' => 'license-canary')

    expect(status).to be_success, output
    expect(File.read(path)).to eq("license-canary\n")
  end

  it 'applies the mode' do
    path = File.join(workdir, 'id-control_repo.rsa')

    output, status = run_task('path' => path, 'content' => '-----BEGIN key', 'mode' => '0600')

    expect(status).to be_success, output
    expect(File.stat(path).mode & 0o777).to eq(0o600)
  end

  it 'leaves owner, group and mode alone when they are not given' do
    path = File.join(workdir, 'autosign.conf')
    File.write(path, '')
    File.chmod(0o640, path)

    output, status = run_task('path' => path, 'content' => "postgres1\n", 'owner' => nil)

    expect(status).to be_success, output
    expect(File.stat(path).mode & 0o777).to eq(0o640)
  end
end
