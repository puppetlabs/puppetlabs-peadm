require 'spec_helper'

describe 'peadm::util::check_installer_source' do
  include BoltSpec::Plans

  let(:source) { 'https://deploy:secret@mirror.example.com/pe/puppet-enterprise-2023.8.10-el-9-x86_64.tar.gz' }
  let(:tarball_name) { 'puppet-enterprise-2023.8.10-el-9-x86_64.tar.gz' }
  let(:curl) { 'curl -sSfIL -o /dev/null "$PEADM_INSTALLER_SOURCE"' }
  let(:staged_check) { "test -e /tmp/#{tarball_name}" }

  def params(mode)
    { 'targets' => ['new1', 'new2'], 'source' => source, 'tarball_name' => tarball_name, 'download_mode' => mode }
  end

  def curl_fails_on(failing)
    expect_command(curl).return do |targets:, **_kwargs|
      Bolt::ResultSet.new(targets.map do |target|
        if failing.include?(target.name)
          Bolt::Result.new(target, value: {
                             'stderr' => "curl: (22) The requested URL returned error: 404\n",
                             'exit_code' => 22,
                             '_error' => { 'kind' => 'puppetlabs.tasks/command-error', 'msg' => 'failed' },
                           })
        else
          Bolt::Result.new(target, value: { 'stdout' => '', 'exit_code' => 0 })
        end
      end)
    end
  end

  before(:each) { allow_out_message }

  context 'with download_mode=bolthost' do
    before(:each) { allow_task('peadm::os_identification').always_return({ '_output' => 'linux' }) }

    it 'checks the URL from the Bolt host only, passing it in the environment' do
      allow_command(staged_check).error_with('kind' => 'nope', 'msg' => 'exit code 1')
      expect_command(curl).with_targets(['local://localhost'])
                          .with_params('_catch_errors' => true, '_env_vars' => { 'PEADM_INSTALLER_SOURCE' => source })

      expect(run_plan('peadm::util::check_installer_source', params('bolthost'))).to be_ok
    end

    it 'skips the URL check when the installer is already staged on the Bolt host' do
      expect_command(staged_check)
      expect_command(curl).not_be_called

      expect(run_plan('peadm::util::check_installer_source', params('bolthost'))).to be_ok
    end

    it 'fails without the URL in the message when the Bolt host cannot fetch it' do
      allow_command(staged_check).error_with('kind' => 'nope', 'msg' => 'exit code 1')
      curl_fails_on(['local://localhost'])

      result = run_plan('peadm::util::check_installer_source', params('bolthost'))

      expect(result).not_to be_ok
      expect(result.value.msg).to include(
        "Can't download the PE installer #{tarball_name} from the Bolt host (curl: (22) The requested URL returned error: 404).",
      )
      expect(result.value.msg).to include('Nothing has been changed.')
      expect(result.value.msg).not_to include('secret')
    end

    it 'skips the check on a Windows Bolt host' do
      allow_task('peadm::os_identification').always_return({ '_output' => 'windows' })
      expect_command(curl).not_be_called

      expect(run_plan('peadm::util::check_installer_source', params('bolthost'))).to be_ok
    end
  end

  context 'with download_mode=direct' do
    it 'checks the URL from every target and names the ones that failed' do
      expect_task('peadm::os_identification').not_be_called
      curl_fails_on(['new2'])

      result = run_plan('peadm::util::check_installer_source', params('direct'))

      expect(result).not_to be_ok
      expect(result.value.msg).to include('from new1, new2 (new2: curl: (22) The requested URL returned error: 404)')
    end

    it 'passes when every target can fetch it' do
      expect_command(curl).with_targets(['new1', 'new2'])

      expect(run_plan('peadm::util::check_installer_source', params('direct'))).to be_ok
    end

    # Bolt can't pass environment variables to commands over pcp.
    it 'skips targets that use the pcp transport' do
      expect_command(curl).with_targets(['new1'])

      expect(run_plan('peadm::util::check_installer_source', params('direct').merge('targets' => ['new1', 'pcp://new2']))).to be_ok
    end

    it 'checks nothing when every target uses the pcp transport' do
      expect_command(curl).not_be_called

      expect(run_plan('peadm::util::check_installer_source', params('direct').merge('targets' => ['pcp://new2']))).to be_ok
    end
  end
end
