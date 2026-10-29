# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'open3'
require 'tmpdir'

# PE-47523: pe_installer_source can be a pre-signed URL whose query string
# carries credentials, or a URL with user:password@ in it. download.sh
# describes a URL by its file name and host only, so neither reaches the task
# output, which Bolt logs. (The plans also keep the query string out of the
# download path; see the pe_installer_source examples in the install and
# upgrade plan specs.) The script runs for real, with a fake curl first on
# PATH so nothing touches the network.
describe 'tasks/download.sh' do
  let(:script) { File.expand_path('../../../tasks/download.sh', __dir__) }
  let(:signed_url) do
    'https://bucket.s3.amazonaws.com/released/puppet-enterprise-2023.8.10-el-8-x86_64.tar.gz' \
      '?X-Amz-Credential=AKIA-canary&X-Amz-Signature=signature-canary'
  end
  let(:workdir) { Dir.mktmpdir }

  # Writes a stand-in for the downloaded file and prints no headers for
  # --head, so the size check never matches. Fails for the .asc signature,
  # the way a pre-signed URL with ".asc" appended does, and for everything
  # when FAKE_CURL_FAIL is set.
  let(:fake_curl) do
    <<~CURL
      #!/bin/bash
      [ -n "$FAKE_CURL_FAIL" ] && exit 22
      out=''
      url=''
      while [ $# -gt 0 ]; do
        case "$1" in
          -o) out="$2"; shift 2 ;;
          --head) exit 0 ;;
          -*) shift ;;
          *) url="$1"; shift ;;
        esac
      done
      case "$url" in *.asc) exit 22 ;; esac
      echo payload > "$out"
    CURL
  end

  before(:each) do
    FileUtils.mkdir_p(File.join(workdir, 'bin'))
    File.write(File.join(workdir, 'bin', 'curl'), fake_curl)
    FileUtils.chmod(0o755, File.join(workdir, 'bin', 'curl'))
  end

  after(:each) do
    FileUtils.remove_entry(workdir)
  end

  def run_download(verify_download, source = signed_url, extra_env = {})
    env = {
      'PATH'               => "#{File.join(workdir, 'bin')}:#{ENV.fetch('PATH')}",
      'PT_source'          => source,
      'PT_path'            => File.join(workdir, 'pe.tar.gz'),
      'PT_verify_download' => verify_download.to_s,
      'PT_key_server'      => 'hkp://keyserver.example.com:80',
    }.merge(extra_env)
    Open3.capture2e(env, 'bash', script)
  end

  [true, false].each do |verify_download|
    context "with verify_download=#{verify_download}" do
      it 'prints the file name and host but not the query string' do
        output, status = run_download(verify_download)

        expect(status).to be_success, output
        expect(File.read(File.join(workdir, 'pe.tar.gz'))).to eq("payload\n")
        expect(output).to include('Downloading: puppet-enterprise-2023.8.10-el-8-x86_64.tar.gz from bucket.s3.amazonaws.com')
        expect(output).not_to include('?')
        expect(output).not_to include('canary')
      end
    end
  end

  it 'names the .asc signature when it tries to download one' do
    output, status = run_download(true)

    expect(status).to be_success, output
    expect(output).to include('Downloading: the .asc signature for puppet-enterprise-2023.8.10-el-8-x86_64.tar.gz from bucket.s3.amazonaws.com')
  end

  it "reports curl's exit code, but not the query string, when the download fails" do
    output, status = run_download(false, signed_url, 'FAKE_CURL_FAIL' => '1')

    expect(status).not_to be_success
    expect(output).to include('Error: curl exited with 22 downloading puppet-enterprise-2023.8.10-el-8-x86_64.tar.gz from bucket.s3.amazonaws.com')
    expect(output).not_to include('canary')
  end

  {
    'https://pe-user:password-canary@artifacts.example.com/pe/puppet-enterprise.tar.gz' => 'puppet-enterprise.tar.gz from artifacts.example.com',
    'https://pe-user:password-canary@artifacts.example.com?id=1-canary'                 => 'artifacts.example.com',
    'https://artifacts.example.com/pe/puppet-enterprise.tar.gz#fragment-canary'         => 'puppet-enterprise.tar.gz from artifacts.example.com',
    'https://[2001:db8::1]:8443/pe/puppet-enterprise.tar.gz'                            => 'puppet-enterprise.tar.gz from [2001:db8::1]:8443',
    'file:///srv/pe/puppet-enterprise.tar.gz'                                           => 'puppet-enterprise.tar.gz',
    # Raw / or ? in the password make the URL ambiguous; nothing from the
    # user info may print.
    'https://pe-user:tok-canary/rest-canary@artifacts.example.com/pe.tar.gz'            => 'pe.tar.gz',
    'https://pe-user:pass?word-canary@artifacts.example.com/pe.tar.gz'                  => 'the source URL',
  }.each do |source, description|
    it "describes #{source} as \"#{description}\"" do
      output, status = run_download(false, source)

      expect(status).to be_success, output
      expect(output).to include("Downloading: #{description}\n")
      expect(output).not_to include('canary')
    end
  end
end
