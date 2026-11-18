# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'open3'
require 'tmpdir'

# PE-47521: tasks/code_manager.sh exits non-zero when curl fails or the server
# returns a non-2xx status. These examples run the real script under bash, with
# stub `curl` and `su` commands first on PATH, so they test the shell as
# shipped. The script reads the certname with /opt/puppetlabs/bin/puppet, an
# absolute path a PATH stub can't replace; where it is missing the certname is
# empty, which the curl stub ignores.
describe 'tasks/code_manager.sh' do
  let(:script) { File.expand_path('../../../tasks/code_manager.sh', __dir__) }
  let(:stub_dir) { Dir.mktmpdir('code_manager_spec') }
  let(:calls_log) { File.join(stub_dir, 'calls.log') }

  # Prints $STUB_BODY, then the -w format with %{http_code} set to
  # $STUB_HTTP_CODE (default 200). If $STUB_CURL_EXIT is set, it instead writes
  # 000 as the code and exits with that status, printing a connection error to
  # stderr only when given -S, as curl does under -s. If $STUB_CURL_FAIL_ON is
  # set, only calls whose URL contains it get the failure; the rest get 200.
  # Each call's URL (the last argument) is appended to calls.log.
  let(:curl_stub) do
    <<~'SH'
      #!/bin/bash
      url="${!#}"
      echo "curl $url" >> "$STUB_CALLS_LOG"
      format=''
      show_error=''
      while [ "$#" -gt 0 ]; do
        case "$1" in
          -w) format="$2"; shift ;;
          -S) show_error=1 ;;
        esac
        shift
      done
      targeted=1
      if [ -n "${STUB_CURL_FAIL_ON:-}" ] && [[ "$url" != *"$STUB_CURL_FAIL_ON"* ]]; then
        targeted=''
      fi
      if [ -n "$targeted" ] && [ -n "${STUB_CURL_EXIT:-}" ]; then
        [ -n "$show_error" ] && echo "curl: (${STUB_CURL_EXIT}) Failed to connect to localhost port 8140: Connection refused" >&2
        printf '%b' "${format//%\{http_code\}/000}"
        exit "$STUB_CURL_EXIT"
      fi
      code=200
      [ -n "$targeted" ] && code="${STUB_HTTP_CODE:-200}"
      printf '%s' "${STUB_BODY:-}"
      printf '%b' "${format//%\{http_code\}/$code}"
      exit 0
    SH
  end

  let(:su_stub) do
    <<~'SH'
      #!/bin/bash
      echo "su $*" >> "$STUB_CALLS_LOG"
      exit "${STUB_SU_EXIT:-0}"
    SH
  end

  before(:each) do
    skip 'needs bash' if Gem.win_platform?
    { 'curl' => curl_stub, 'su' => su_stub }.each do |name, body|
      path = File.join(stub_dir, name)
      File.write(path, body)
      FileUtils.chmod(0o755, path)
    end
  end

  after(:each) { FileUtils.remove_entry(stub_dir) }

  def run_script(action, env = {})
    full_env = {
      'PATH' => "#{stub_dir}:#{ENV.fetch('PATH')}",
      'PT_action' => action,
      'STUB_CALLS_LOG' => calls_log,
    }.merge(env)
    stdout, stderr, status = Open3.capture3(full_env, 'bash', script)
    { stdout: stdout, stderr: stderr, out: stdout + stderr, status: status }
  end

  def calls
    File.exist?(calls_log) ? File.readlines(calls_log, chomp: true) : []
  end

  {
    'file-sync commit' => 'file-sync/v1/commit',
    'file-sync force-sync' => 'file-sync/v1/force-sync',
    'flush-environment-cache' => 'puppet-admin-api/v1/environment-cache',
  }.each do |action, endpoint|
    context "with action '#{action}'" do
      it 'exits 0 when the server returns 200' do
        result = run_script(action, 'STUB_BODY' => '{"ok":true}')

        expect(result[:status].exitstatus).to eq(0), result[:out]
        expect(calls).to eq(["curl https://localhost:8140/#{endpoint}"])
      end

      it "exits non-zero and prints curl's error when curl fails" do
        result = run_script(action, 'STUB_CURL_EXIT' => '7')

        expect(result[:status].exitstatus).to eq(7)
        expect(result[:stderr]).to include(
          "curl exited 7 calling https://localhost:8140/#{endpoint}: curl: (7) Failed to connect to localhost port 8140",
        )
        expect(result[:stdout]).to be_empty
      end

      it 'exits non-zero and prints the body when the server returns 500' do
        body = '{"kind":"puppetlabs.file-sync/commit-error","msg":"canary failure body"}'
        result = run_script(action, 'STUB_HTTP_CODE' => '500', 'STUB_BODY' => body)

        expect(result[:status].exitstatus).to eq(1)
        expect(result[:stderr]).to include("HTTP 500 from https://localhost:8140/#{endpoint}: #{body}")
        expect(result[:stdout]).to be_empty
      end
    end
  end

  it 'exits 0, printing nothing, when the server returns 204 with no body' do
    result = run_script('flush-environment-cache', 'STUB_HTTP_CODE' => '204')

    expect(result[:status].exitstatus).to eq(0), result[:out]
    expect(result[:stdout]).to be_empty
  end

  it 'takes the status from the last line when the body spans several lines' do
    body = "{\n  \"kind\": \"error\",\n  \"msg\": \"200\"\n}"
    result = run_script('file-sync commit', 'STUB_HTTP_CODE' => '500', 'STUB_BODY' => body)

    expect(result[:status].exitstatus).to eq(1)
    expect(result[:stderr]).to include("HTTP 500 from https://localhost:8140/file-sync/v1/commit: #{body}")
  end

  ['302', '404'].each do |code|
    it "exits non-zero when the server returns #{code}" do
      result = run_script('file-sync commit', 'STUB_HTTP_CODE' => code)

      expect(result[:status].exitstatus).to eq(1)
      expect(result[:stderr]).to include("HTTP #{code} from")
    end
  end

  # commit skips the force-sync when the commit fails, and fails either way.
  context "with action 'commit'" do
    it 'commits then force-syncs, and exits 0, when both succeed' do
      result = run_script('commit')

      expect(result[:status].exitstatus).to eq(0), result[:out]
      expect(calls).to eq(['curl https://localhost:8140/file-sync/v1/commit',
                           'curl https://localhost:8140/file-sync/v1/force-sync'])
    end

    it 'fails without force-syncing when the commit fails' do
      result = run_script('commit', 'STUB_HTTP_CODE' => '500', 'STUB_CURL_FAIL_ON' => 'file-sync/v1/commit')

      expect(result[:status].exitstatus).to eq(1)
      expect(result[:stderr]).to include('HTTP 500 from https://localhost:8140/file-sync/v1/commit')
      expect(calls).to eq(['curl https://localhost:8140/file-sync/v1/commit'])
    end

    it 'fails when the force-sync fails after a good commit' do
      result = run_script('commit', 'STUB_CURL_EXIT' => '7', 'STUB_CURL_FAIL_ON' => 'force-sync')

      expect(result[:status].exitstatus).to eq(7)
      expect(result[:stderr]).to include('curl exited 7 calling https://localhost:8140/file-sync/v1/force-sync')
      expect(calls).to eq(['curl https://localhost:8140/file-sync/v1/commit',
                           'curl https://localhost:8140/file-sync/v1/force-sync'])
    end
  end

  context "with action 'deploy production'" do
    it 'runs r10k then commits, and exits 0, when all succeed' do
      result = run_script('deploy production')

      expect(result[:status].exitstatus).to eq(0), result[:out]
      expect(calls.first).to start_with('su - pe-puppet')
      expect(calls.first).to include('deploy environment production -p')
      expect(calls.drop(1)).to eq(['curl https://localhost:8140/file-sync/v1/commit',
                                   'curl https://localhost:8140/file-sync/v1/force-sync'])
    end

    it 'fails without committing when r10k fails' do
      result = run_script('deploy production', 'STUB_SU_EXIT' => '1')

      expect(result[:status].exitstatus).to eq(1)
      expect(calls.grep(%r{^curl})).to be_empty
    end

    it 'fails when the commit after r10k fails' do
      result = run_script('deploy production', 'STUB_HTTP_CODE' => '503', 'STUB_BODY' => 'unavailable')

      expect(result[:status].exitstatus).to eq(1)
      expect(result[:stderr]).to include('HTTP 503 from https://localhost:8140/file-sync/v1/commit')
    end
  end

  it 'keeps the -v output, including the exit code, on success' do
    result = run_script('-v file-sync commit', 'STUB_BODY' => '{"ok":true}')

    expect(result[:status].exitstatus).to eq(0), result[:out]
    expect(result[:out]).to include('command: curl')
    expect(result[:out]).to include('exitcode: 0')
    expect(result[:out]).to include('http_code: 200')
  end

  it 'keeps the -v output, and still fails, when the server returns 500' do
    result = run_script('-v file-sync commit', 'STUB_HTTP_CODE' => '500', 'STUB_BODY' => 'broken')

    expect(result[:status].exitstatus).to eq(1)
    expect(result[:out]).to include('http_code: 500')
    expect(result[:stderr]).to include('HTTP 500 from https://localhost:8140/file-sync/v1/commit: broken')
  end
end
