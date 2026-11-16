# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'open3'
require 'fileutils'
require 'tmpdir'

# tasks/read_file.sh is a shell script that hands the read to Python, so these
# examples run the real script against temporary files instead of stubbing.
describe 'peadm::read_file task' do
  let(:script) { File.expand_path('../../../tasks/read_file.sh', __dir__) }
  let(:dir) { Dir.mktmpdir('read_file_spec') }

  python_available = ['python', 'python3', 'python2'].any? { |py| system("command -v #{py} >/dev/null 2>&1") }

  before(:each) do
    skip 'no Python interpreter on this host' unless python_available
  end

  after(:each) do
    FileUtils.chmod_R('u+rwx', dir)
    FileUtils.remove_entry(dir)
  end

  # Runs the task with PT_path set, from inside the temp directory, so any
  # command a crafted path manages to run would leave its marker file there.
  def run_task(path, env = {})
    stdout, stderr, status = Open3.capture3(env.merge('PT_path' => path), 'bash', script, chdir: dir)
    { stdout: stdout, stderr: stderr, exitstatus: status.exitstatus }
  end

  def write_file(name, content, mode: 'w')
    path = File.join(dir, name)
    File.open(path, mode) { |f| f.write(content) }
    path
  end

  def markers
    Dir.children(dir).select { |name| name.start_with?('pwned') }
  end

  it 'returns the content of a readable file' do
    result = run_task(write_file('plain.txt', "plain\n"))

    expect(result[:exitstatus]).to eq(0)
    expect(JSON.parse(result[:stdout])).to eq('content' => "plain\n")
  end

  it 'returns the content byte for byte, including CRLF line endings' do
    result = run_task(write_file('crlf.txt', "a\r\nb\n", mode: 'wb'))

    expect(result[:exitstatus]).to eq(0)
    expect(JSON.parse(result[:stdout])).to eq('content' => "a\r\nb\n")
  end

  it 'reads UTF-8 content even when the locale is C' do
    result = run_task(write_file('utf8.txt', "café\n", mode: 'w:UTF-8'), 'LC_ALL' => 'C', 'LANG' => 'C')

    expect(result[:exitstatus]).to eq(0)
    expect(JSON.parse(result[:stdout])).to eq('content' => "café\n")
  end

  # The path used to be spliced into `python -c "...open('$PT_path')..."`, so
  # a single quote in the path ended the Python string and ran the rest.
  it 'reads a path containing a Python injection as an ordinary path, without running it' do
    path = write_file("a'+__import__('os').system('touch pwned_py')+'.txt", "hello\n")

    result = run_task(path)

    expect(markers).to be_empty
    expect(result[:exitstatus]).to eq(0)
    expect(JSON.parse(result[:stdout])).to eq('content' => "hello\n")
  end

  it 'reads a path containing shell metacharacters as an ordinary path, without running them' do
    path = write_file('b$(touch pwned_sub)`touch pwned_tick`;touch pwned_semi;".txt', "meta\n")

    result = run_task(path)

    expect(markers).to be_empty
    expect(result[:exitstatus]).to eq(0)
    expect(JSON.parse(result[:stdout])).to eq('content' => "meta\n")
  end

  it 'reports a missing crafted path as missing, without running it' do
    result = run_task(File.join(dir, "c'+__import__('os').system('touch pwned_missing')+'.txt"))

    expect(markers).to be_empty
    expect(result[:exitstatus]).to eq(0)
    expect(JSON.parse(result[:stdout])).to eq('content' => nil, 'error' => 'File does not exist or is not readable')
  end

  it 'returns content null and the error key for a missing file' do
    result = run_task(File.join(dir, 'missing.txt'))

    expect(result[:exitstatus]).to eq(0)
    expect(JSON.parse(result[:stdout])).to eq('content' => nil, 'error' => 'File does not exist or is not readable')
  end

  it 'returns content null and the error key for an unreadable file' do
    skip 'root can read any file' if Process.uid.zero?
    path = write_file('secret.txt', "secret\n")
    File.chmod(0o000, path)

    result = run_task(path)

    expect(result[:exitstatus]).to eq(0)
    expect(JSON.parse(result[:stdout])).to eq('content' => nil, 'error' => 'File does not exist or is not readable')
  end

  it 'reports a directory as not readable' do
    result = run_task(dir)

    expect(result[:exitstatus]).to eq(0)
    expect(JSON.parse(result[:stdout])).to eq('content' => nil, 'error' => 'File does not exist or is not readable')
  end

  it 'fails with a peadm/read-file-error and valid JSON when the file is not UTF-8' do
    path = write_file('bad.bin', "ok\xff\xfe\x80bad\n".b, mode: 'wb')

    result = run_task(path)

    expect(result[:exitstatus]).to eq(1)
    error = JSON.parse(result[:stdout]).fetch('_error')
    expect(error['kind']).to eq('peadm/read-file-error')
    expect(error['msg']).to include(path)
    expect(error['details']).to eq('path' => path)
  end
end
