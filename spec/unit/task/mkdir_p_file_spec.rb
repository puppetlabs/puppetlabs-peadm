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
# variables. The script runs for real, with only stdin input. Recording
# chown, chgrp and chmod come first on PATH, so ownership needs no root.
describe 'tasks/mkdir_p_file.sh' do
  let(:script) { File.expand_path('../../../tasks/mkdir_p_file.sh', __dir__) }
  let(:workdir) { Dir.mktmpdir }
  let(:bin_dir) { File.join(workdir, 'bin') }
  let(:calls_log) { File.join(workdir, 'calls.log') }

  before(:each) do
    FileUtils.mkdir_p(bin_dir)
    ['chown', 'chgrp'].each do |command|
      File.write(File.join(bin_dir, command), "#!/bin/bash\necho \"#{command} $*\" >> '#{calls_log}'\n")
    end
    # Also records how many bytes the file holds when its mode is set, which
    # must be none: the mode has to be in place before the secret is written.
    File.write(File.join(bin_dir, 'chmod'), <<~SH)
      #!/bin/bash
      echo "chmod $* size=$(wc -c < "${@: -1}" | tr -d ' ')" >> '#{calls_log}'
      exec '#{`command -v chmod`.strip}' "$@"
    SH
    ['chown', 'chgrp', 'chmod'].each { |command| FileUtils.chmod(0o755, File.join(bin_dir, command)) }
  end

  after(:each) do
    FileUtils.remove_entry(workdir)
  end

  # Bolt adds _task to stdin input.
  def run_mkdir_p_file(params)
    env = { 'PATH' => "#{bin_dir}:#{ENV.fetch('PATH')}" }
    Open3.capture2e(env, 'bash', script, stdin_data: params.merge('_task' => 'peadm::mkdir_p_file').to_json)
  end

  def calls
    File.exist?(calls_log) ? File.readlines(calls_log, chomp: true) : []
  end

  it 'writes the content verbatim, plus a newline, creating missing directories' do
    path = File.join(workdir, 'conf.d', 'pe.conf')
    content = <<~'PECONF'.chomp
      {
        "console_admin_password": "$(id) `id` $HOME \\ \"q\" é"
      }
    PECONF

    output, status = run_mkdir_p_file('path' => path, 'content' => content)

    expect(status).to be_success, output
    expect(File.read(path, encoding: 'UTF-8')).to eq("#{content}\n")
  end

  it 'replaces the content of an existing file' do
    path = File.join(workdir, 'license.key')
    File.write(path, "old content that is longer than the new one\n")

    output, status = run_mkdir_p_file('path' => path, 'content' => 'license-canary')

    expect(status).to be_success, output
    expect(File.read(path)).to eq("license-canary\n")
  end

  it 'sets owner, group, mode and chown_r, and the mode before writing the content' do
    chown_r = File.join(workdir, 'code-staging', 'environments')
    path = File.join(chown_r, 'production', 'manifests', 'site.pp')

    output, status = run_mkdir_p_file('path' => path, 'content' => 'key-canary', 'owner' => 'pe-puppet', 'group' => 'pe-puppet',
                                      'mode' => '0600', 'chown_r' => chown_r)

    expect(status).to be_success, output
    expect(calls).to eq([
                          "chown pe-puppet #{path}",
                          "chgrp pe-puppet #{path}",
                          "chmod 0600 #{path} size=0",
                          "chown -R pe-puppet:pe-puppet #{chown_r}",
                        ])
    expect(File.stat(path).mode & 0o777).to eq(0o600)
    expect(File.read(path)).to eq("key-canary\n")
  end

  # The script needs Python; without it, it says so and fails
  it 'fails with a message when the target has no Python interpreter' do
    bare = File.join(workdir, 'bare')
    FileUtils.mkdir_p(bare)
    File.symlink(`command -v cat`.strip, File.join(bare, 'cat'))
    path = File.join(workdir, 'pe.conf')

    output, status = Open3.capture2e({ 'PATH' => bare }, '/bin/bash', script,
                                     stdin_data: { 'path' => path, 'content' => 'x', '_task' => 'peadm::mkdir_p_file' }.to_json)

    expect(status).not_to be_success
    expect(output).to include('No Python version 2 or 3 interpreter found.')
    expect(File.exist?(path)).to be(false)
  end

  it 'leaves owner, group and mode alone when they are null or not given' do
    path = File.join(workdir, 'autosign.conf')
    File.write(path, '')
    File.chmod(0o640, path)

    output, status = run_mkdir_p_file('path' => path, 'content' => "postgres1\n", 'owner' => nil)

    expect(status).to be_success, output
    expect(calls).to be_empty
    expect(File.stat(path).mode & 0o777).to eq(0o640)
  end
end
