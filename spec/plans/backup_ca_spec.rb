require 'spec_helper'

describe 'peadm::backup_ca' do
  include BoltSpec::Plans

  let(:params) { { 'target' => 'myserver.example.com' } }
  let(:backup_dir) { '/tmp/pe-backup-1970-01-01T000000Z' }
  let(:make_dir) { "mkdir -m 0711 #{backup_dir}" }
  let(:ca_export) { '/opt/puppetlabs/bin/puppetserver ca storage --export' }
  let(:certs_backup) { "umask 0077 && /opt/puppetlabs/bin/puppet-backup create --dir=#{backup_dir} --name=ca_backup.tgz --scope=certs\n" }

  before(:each) do
    # Fixed timestamp, so the backup directory is always /tmp/pe-backup-1970-01-01T000000Z
    allow(Puppet::Pops::Time::Timestamp).to receive(:now).and_return(Puppet::Pops::Time::Timestamp.new(0))
  end

  # Runs the plan with the CA backend check answering `backend`, and returns
  # the plan result and every command run, in order. A command containing
  # `fail_on` returns an error instead.
  def run_with_ca_backend(backend, plan_params = params, fail_on: nil)
    call_log = []
    allow_out_message
    allow_any_command.return do |targets:, command:, **|
      call_log << command
      results = targets.map do |target|
        if fail_on && command.include?(fail_on)
          Bolt::Result.new(target, error: { 'msg' => 'failed', 'kind' => 'peadm/test-failure' })
        else
          stdout = command.include?('database-storage-service') ? "#{backend}\n" : ''
          Bolt::Result.new(target, value: { 'stdout' => stdout })
        end
      end
      Bolt::ResultSet.new(results)
    end
    [run_plan('peadm::backup_ca', plan_params), call_log]
  end

  # puppet-backup stages part of a certs backup as pe-postgres, which cannot
  # enter a root-only 0700 directory; mkdir without -p refuses an existing one
  # (PE-48629). The archive (CA private key) is written under umask 0077.
  it 'creates a new 0711 backup directory, then backs up under umask 0077' do
    result, call_log = run_with_ca_backend('filesystem')
    expect(result).to be_ok
    expect(call_log).to include(make_dir, certs_backup)
    expect(call_log.index(make_dir)).to be < call_log.index(certs_backup)
  end

  it 'shell-quotes a custom output_directory and returns the archive path inside it' do
    custom = '/backups/my dir'
    dir = "#{custom}/pe-backup-1970-01-01T000000Z"
    result, call_log = run_with_ca_backend('filesystem', params.merge('output_directory' => custom))
    expect(result).to be_ok
    expect(call_log).to include(%(mkdir -m 0711 "#{dir}"))
    expect(call_log).to include(%(umask 0077 && /opt/puppetlabs/bin/puppet-backup create --dir="#{dir}" --name=ca_backup.tgz --scope=certs\n))
    expect(result.value).to eq('path' => "#{dir}/ca_backup.tgz")
  end

  it 'returns the path of the CA backup archive' do
    result, = run_with_ca_backend('filesystem')
    expect(result.value).to eq('path' => "#{backup_dir}/ca_backup.tgz")
  end

  # With a database-backed CA the on-disk CA files (incl. the serial counter)
  # lag behind the pe-ca database, so they must be exported first.
  it 'exports a database-backed CA to disk before backing up the certs scope' do
    result, call_log = run_with_ca_backend('database')
    expect(result).to be_ok
    expect(call_log).to include(certs_backup)
    expect(call_log.count(ca_export)).to eq(1)
    expect(call_log.index(ca_export)).to be < call_log.index(certs_backup)
  end

  it 'does not export a filesystem-backed CA' do
    result, call_log = run_with_ca_backend('filesystem')
    expect(result).to be_ok
    expect(call_log).to include(certs_backup)
    expect(call_log).not_to include(ca_export)
  end

  it 'stops before backing up when the CA export fails' do
    result, call_log = run_with_ca_backend('database', fail_on: 'ca storage --export')
    expect(result).not_to be_ok
    expect(call_log).not_to include(certs_backup)
  end

  # A failed mkdir (folder already exists, perhaps planted) must stop the plan.
  it 'stops before backing up when the backup directory cannot be created' do
    result, call_log = run_with_ca_backend('filesystem', fail_on: 'mkdir -m 0711')
    expect(result).not_to be_ok
    expect(call_log).not_to include(certs_backup)
  end

  # A relative path (or a Windows path, which is relative on a Linux primary)
  # would land in the remote shell's working directory.
  ['backups', 'C:/backups'].each do |dir|
    it "rejects output_directory #{dir} before running anything" do
      result, call_log = run_with_ca_backend('filesystem', params.merge('output_directory' => dir))
      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{output_directory})
      expect(call_log).to be_empty
    end
  end
end
