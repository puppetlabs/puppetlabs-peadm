# frozen_string_literal: true

require 'rspec'
require 'tmpdir'
require_relative '../../../tasks/remove_console_password'

describe RemoveConsolePassword do
  around do |example|
    Dir.mktmpdir('peadm-cleanup-test') do |dir|
      @dir = dir
      example.run
    end
  end

  let(:path) { File.join(@dir, 'params.json') }
  let(:keys) { ['console_password', 'console_admin_password'] }
  let(:retained) do
    { 'primary_host' => 'primary.example.com',
      'ldap_config' => { 'password' => 'ldap-password' },
      'pe_conf_data' => { 'database_password' => 'database-password' },
      'r10k_private_key_content' => 'private-key',
      'license_key_content' => 'license' }
  end

  it 'removes only the local top-level console password keys and preserves mode' do
    File.write(path, JSON.generate(retained.merge('console_password' => 'secret', 'console_admin_password' => 'secret')))
    File.chmod(0o600, path)
    result = described_class.clean(path, keys)
    expect(result['changed']).to be(true)
    expect(result.to_json).not_to include('secret')
    expect(JSON.parse(File.read(path))).to eq(retained)
    expect(File.stat(path).mode & 0o777).to eq(0o600)
    expect(described_class.clean(path, keys)['changed']).to be(false)
    expect(Dir.children(@dir)).to eq(['params.json'])
  end

  it 'removes the temporary pe.conf password without modifying running config or license files' do
    running = File.join(@dir, 'running-pe.conf')
    license = File.join(@dir, 'license.key')
    original = JSON.generate(retained.merge('console_admin_password' => 'secret'))
    [path, running].each { |file| File.write(file, original) }
    File.write(license, 'license')
    described_class.clean(path, ['console_admin_password'])
    expect(JSON.parse(File.read(path))).to eq(retained)
    expect(File.read(running)).to eq(original)
    expect(File.read(license)).to eq('license')
  end

  it 'skips missing files' do
    expect(described_class.clean(path, keys)).to eq('changed' => false, 'reason' => 'missing')
  end

  it 'rejects invalid JSON without leaking parser excerpts or changing the file' do
    File.write(path, '{"console_password": "secret"')
    original = File.read(path)
    expect { described_class.clean(path, keys) }.to raise_error(RuntimeError, 'Expected a JSON object; the file was not modified')
    expect(File.read(path)).to eq(original)
  end

  it 'rejects non-object JSON' do
    File.write(path, '[]')
    expect { described_class.clean(path, keys) }.to raise_error(RuntimeError, /Expected a JSON object/)
    expect(File.read(path)).to eq('[]')
  end

  it 'refuses symbolic links, including dangling links' do
    File.symlink(File.join(@dir, 'missing'), path)
    expect { described_class.clean(path, keys) }.to raise_error(RuntimeError, /not a symbolic link/)
  end

  it 'refuses hard links to protect other configuration paths' do
    File.write(path, '{"console_password":"secret"}')
    File.link(path, File.join(@dir, 'another-config'))
    expect { described_class.clean(path, keys) }.to raise_error(RuntimeError, /multiple hard links/)
    expect(JSON.parse(File.read(path))['console_password']).to eq('secret')
  end
end
