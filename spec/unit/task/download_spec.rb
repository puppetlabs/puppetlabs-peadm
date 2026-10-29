# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'open3'
require 'tmpdir'

# PE-47523: pe_installer_source can be a pre-signed URL whose query string
# carries credentials. download.sh printed the full URL, so they ended up in
# Bolt's output. It now prints only the host and the file name. The script
# runs for real, with a fake curl first on PATH so nothing touches the
# network.
describe 'tasks/download.sh' do
  let(:script) { File.expand_path('../../../tasks/download.sh', __dir__) }
  let(:signed_url) do
    'https://bucket.s3.amazonaws.com/released/puppet-enterprise-2023.8.10-el-8-x86_64.tar.gz' \
      '?X-Amz-Credential=AKIA-canary&X-Amz-Signature=signature-canary'
  end
  let(:workdir) { Dir.mktmpdir }

  # Writes a stand-in for the downloaded file, prints no headers for --head
  # (so the size check never matches), and fails for the .asc signature, the
  # way a pre-signed URL with ".asc" appended does.
  let(:fake_curl) do
    <<~CURL
      #!/bin/bash
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

  def run_download(verify_download, source = signed_url)
    env = {
      'PATH'               => "#{File.join(workdir, 'bin')}:#{ENV.fetch('PATH')}",
      'PT_source'          => source,
      'PT_path'            => File.join(workdir, 'pe.tar.gz'),
      'PT_verify_download' => verify_download.to_s,
      'PT_key_server'      => 'hkp://keyserver.example.com:80',
    }
    Open3.capture2e(env, 'bash', script)
  end

  [true, false].each do |verify_download|
    context "with verify_download=#{verify_download}" do
      it 'prints the host and file name but not the query string' do
        output, status = run_download(verify_download)

        expect(status).to be_success, output
        expect(File.read(File.join(workdir, 'pe.tar.gz'))).to eq("payload\n")
        expect(output).to include('puppet-enterprise-2023.8.10-el-8-x86_64.tar.gz from bucket.s3.amazonaws.com')
        expect(output).not_to include('?')
        expect(output).not_to include('canary')
      end
    end
  end

  it 'drops user:password@ from the host it prints' do
    output, status = run_download(false, 'https://pe-user:password-canary@artifacts.example.com/pe/puppet-enterprise.tar.gz')

    expect(status).to be_success, output
    expect(output).to include('Downloading: puppet-enterprise.tar.gz from artifacts.example.com')
    expect(output).not_to include('canary')
  end

  it 'prints only the file name when the URL has no host' do
    output, status = run_download(false, 'file:///srv/pe/puppet-enterprise.tar.gz')

    expect(status).to be_success, output
    expect(output).to include("Downloading: puppet-enterprise.tar.gz\n")
  end
end
