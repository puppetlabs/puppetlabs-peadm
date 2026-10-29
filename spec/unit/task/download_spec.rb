# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'open3'
require 'tmpdir'

# PE-47523: pe_installer_source can be a pre-signed URL whose query string
# carries credentials, or a URL with user:password@ in it. download.sh
# describes a URL by its file name and host only, so neither reaches the task
# output, which Bolt logs. (The plans keep both out of the download path too:
# see spec/functions/url_file_name_spec.rb, and the pe_installer_source
# examples in spec/plans/subplans/install_spec.rb and spec/plans/upgrade_spec.rb.)
# The script runs for real, with a fake curl first on PATH so nothing touches
# the network.
describe 'tasks/download.sh' do
  let(:script) { File.expand_path('../../../tasks/download.sh', __dir__) }
  # A raw / inside the query, as in an AWS credential scope
  let(:signed_url) do
    'https://bucket.s3.amazonaws.com/released/puppet-enterprise-2023.8.10-el-8-x86_64.tar.gz' \
      '?X-Amz-Credential=AKIA-canary/20261029/us-east-1/s3/aws4_request&X-Amz-Signature=signature-canary'
  end
  let(:workdir) { Dir.mktmpdir }
  let(:bin_dir) { File.join(workdir, 'bin') }
  let(:download_path) { File.join(workdir, 'pe.tar.gz') }

  # Writes a stand-in for the downloaded file and prints no headers for
  # --head, so the size check never matches. Fails for the .asc signature,
  # the way a pre-signed URL with ".asc" appended does, and for everything,
  # with curl's own error text, when FAKE_CURL_FAIL is set.
  let(:fake_curl) do
    <<~CURL
      #!/bin/bash
      if [ -n "$FAKE_CURL_FAIL" ]; then
        echo 'curl: (22) The requested URL returned error: 403' >&2
        exit 22
      fi
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
    FileUtils.mkdir_p(bin_dir)
    File.write(File.join(bin_dir, 'curl'), fake_curl)
    FileUtils.chmod(0o755, File.join(bin_dir, 'curl'))
  end

  after(:each) do
    FileUtils.remove_entry(workdir)
  end

  def run_download(verify_download:, source: signed_url, curl_fails: false)
    env = {
      'PATH'               => "#{bin_dir}:#{ENV.fetch('PATH')}",
      'PT_source'          => source,
      'PT_path'            => download_path,
      'PT_verify_download' => verify_download.to_s,
      'PT_key_server'      => 'hkp://keyserver.example.com:80',
    }
    env['FAKE_CURL_FAIL'] = '1' if curl_fails
    Open3.capture2e(env, 'bash', script)
  end

  [true, false].each do |verify_download|
    context "with verify_download=#{verify_download}" do
      it 'prints the file name and host but not the query string' do
        output, status = run_download(verify_download: verify_download)

        expect(status).to be_success, output
        expect(File.read(download_path)).to eq("payload\n")
        expect(output).to include('Downloading: puppet-enterprise-2023.8.10-el-8-x86_64.tar.gz from bucket.s3.amazonaws.com')
        expect(output).not_to include('?')
        expect(output).not_to include('canary')
      end
    end
  end

  it 'names the .asc signature when it tries to download one' do
    output, status = run_download(verify_download: true)

    expect(status).to be_success, output
    expect(output).to include('Downloading: the .asc signature for puppet-enterprise-2023.8.10-el-8-x86_64.tar.gz from bucket.s3.amazonaws.com')
  end

  it "reports curl's exit code and error, but not the query string, when the download fails" do
    output, status = run_download(verify_download: false, curl_fails: true)

    expect(status).not_to be_success
    expect(output).to include('Error: curl exited with 22 downloading puppet-enterprise-2023.8.10-el-8-x86_64.tar.gz from bucket.s3.amazonaws.com: ' \
                              'curl: (22) The requested URL returned error: 403')
    expect(output).not_to include('canary')
  end

  {
    'https://user-canary:password-canary@artifacts.example.com/pe/puppet-enterprise.tar.gz' => 'puppet-enterprise.tar.gz from artifacts.example.com',
    'https://user-canary:password-canary@artifacts.example.com?id=1-canary'                 => 'artifacts.example.com',
    'https://artifacts.example.com/pe/puppet-enterprise.tar.gz#fragment-canary'             => 'puppet-enterprise.tar.gz from artifacts.example.com',
    'https://[2001:db8::1]:8443/pe/puppet-enterprise.tar.gz'                                => 'puppet-enterprise.tar.gz from [2001:db8::1]:8443',
    'file:///srv/pe/puppet-enterprise.tar.gz'                                               => 'puppet-enterprise.tar.gz',
    # A raw / ? or # in the password makes it impossible to tell where the
    # user info ends, so nothing of the URL may print.
    'https://user-canary:tok-canary/rest-canary@artifacts.example.com/pe.tar.gz'            => 'the source URL',
    'https://user-canary:tok-canary/rest-canary@artifacts.example.com'                      => 'the source URL',
    'https://user-canary:2024/secret-canary@artifacts.example.com/pe.tar.gz'                => 'the source URL',
    'https://user-canary:pass?word-canary@artifacts.example.com/pe.tar.gz'                  => 'the source URL',
    'https://user-canary:123456?abc-canary@artifacts.example.com/pe.tar.gz'                 => 'the source URL',
    'https://user-canary:4821#Ab-canary@artifacts.example.com/pe.tar.gz'                    => 'the source URL',
    'https://token-canary#x@artifacts.example.com/pe.tar.gz'                                => 'the source URL',
  }.each do |source, description|
    it "describes #{source} as \"#{description}\"" do
      output, status = run_download(verify_download: false, source: source)

      expect(status).to be_success, output
      expect(output).to include("Downloading: #{description}\n")
      expect(output).not_to include('canary')
    end
  end
end
