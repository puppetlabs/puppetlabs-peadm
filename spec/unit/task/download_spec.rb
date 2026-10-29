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

  # Writes a stand-in for the downloaded file. Answers --head with
  # Content-Length: 8, the size of the 'payload' it writes, so the size check
  # matches a file holding that. Fails for the .asc signature, the way a
  # pre-signed URL with ".asc" appended does. A URL with [ ] { } is only taken
  # with -g, as with real curl; without it curl prints a two-line error that
  # names the whole URL. With FAKE_CURL_FAIL it fails for everything, printing
  # on stderr what real curl can print: a 403, text holding the URL, or a
  # fragment of it, for a HEAD request as well.
  let(:fake_curl) do
    <<~CURL
      #!/bin/bash
      globoff='' head=''
      out=''
      url=''
      while [ $# -gt 0 ]; do
        case "$1" in
          -o) out="$2"; shift 2 ;;
          --head) head=1; shift ;;
          -*g*) globoff=1; shift ;;
          -*) shift ;;
          *) url="$1"; shift ;;
        esac
      done
      if [[ "$url" == *[\\[\\]{}]* && -z "$globoff" ]]; then
        printf 'curl: (3) unmatched brace in URL position 16:\\n%s\\n' "$url" >&2
        exit 3
      fi
      if [ -n "$head" ] && [ -z "$FAKE_CURL_FAIL" ]; then
        printf 'HTTP/1.1 200 OK\\r\\nContent-Length: 8\\r\\n\\r\\n'
        exit 0
      fi
      case "$FAKE_CURL_FAIL" in
        '') ;;
        forbidden) echo 'curl: (22) The requested URL returned error: 403' >&2; exit 22 ;;
        url) printf 'curl: (3) URL using bad/illegal format: %s\\n' "$url" >&2; exit 3 ;;
        fragment) echo 'curl: (6) Could not resolve host: W0rd-canary@artifacts.example.com' >&2; exit 6 ;;
      esac
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
    env['FAKE_CURL_FAIL'] = curl_fails.to_s if curl_fails
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

  # curl's own text can hold the URL, or part of the URL (what follows the first
  # @ of a password, with some curl versions), so none of it is printed
  {
    forbidden: [22, 'https://bucket.s3.amazonaws.com/released/puppet-enterprise-2023.8.10-el-8-x86_64.tar.gz?X-Amz-Signature=sig-canary'],
    url:       [3, 'https://user-canary:Pw{1-canary@artifacts.example.com/pe/puppet-enterprise.tar.gz?sig=sig-canary'],
    fragment:  [6, 'https://user-canary:P4ss@W0rd-canary@artifacts.example.com/pe/puppet-enterprise.tar.gz'],
  }.each do |mode, (exit_code, source)|
    it "reports only curl's exit code when the download fails (#{mode})" do
      output, status = run_download(verify_download: false, source: source, curl_fails: mode)

      expect(status).not_to be_success
      expect(output).to match(%r{^Error: curl exited with #{exit_code} downloading puppet-enterprise.*tar\.gz( from [a-z0-9.]+)? \(see EXIT CODES in man curl\)$})
      expect(output).not_to include('canary')
      expect(output).not_to include('curl: (')
    end
  end

  # The size check's HEAD request can fail with text that holds the URL too
  [:url, :fragment].each do |mode|
    it "prints none of curl's text when the size check's HEAD request fails (#{mode})" do
      source = 'https://user-canary:P4ss@W0rd-canary@artifacts.example.com/pe/puppet-enterprise.tar.gz?sig=sig-canary'
      output, _status = run_download(verify_download: false, source: source, curl_fails: mode)

      expect(output).not_to include('canary')
      expect(output).not_to include('curl: (')
    end
  end

  # Without -g curl takes [ ] { } in a URL as a glob and rejects it, in the
  # download and in the size check's HEAD request
  [true, false].each do |verify_download|
    source = 'https://artifacts.example.com/pe/puppet-enterprise.tar.gz?filter[a]={b}&sig=sig-canary'

    it "downloads a URL with [ ] { } in its query string (verify_download=#{verify_download})" do
      output, status = run_download(verify_download: verify_download, source: source)

      expect(status).to be_success, output
      expect(File.read(download_path)).to eq("payload\n")
    end

    it "sizes a URL with [ ] { } in its query string with a HEAD request (verify_download=#{verify_download})" do
      File.write(download_path, "payload\n")
      output, status = run_download(verify_download: verify_download, source: source)

      expect(status).to be_success, output
      expect(output).to include('File size matches HTTP Content-Length header')
    end
  end

  {
    'https://host-canary:pw-canary/pe/puppet-enterprise.tar.gz'                                => 'puppet-enterprise.tar.gz',
    'https://artifacts.example.com/dl/token-canary'                                            => 'artifacts.example.com',
    "https://artifacts.example.com/pe/it's.tar.gz"                                             => 'artifacts.example.com',
    'https://artifacts.example.com/ci/puppet-enterprise-2025.4.0+build5-el-8-x86_64.tar'       => 'puppet-enterprise-2025.4.0+build5-el-8-x86_64.tar from artifacts.example.com',
    'https://artifacts.example.com/pe/x.tar.gz-token-canary'                                   => 'artifacts.example.com',
    'https://artifacts.example.com/pe/-rf.tar'                                                 => 'artifacts.example.com',
    # No scheme: the :// in the query isn't one
    'localhost:1/p?next=https://token-canary/x'                                                => 'the source URL',
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
