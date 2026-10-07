require 'spec_helper'
require_relative '../../../tasks/rbac_token'

describe RbacToken do
  subject(:rbac_token) { described_class.new(params) }

  let(:params) { { 'password' => 'supersecret', 'token_lifetime' => '1y' } }
  let(:https_dbl) { instance_double(Net::HTTP) }
  let(:request_dbl) { instance_double(Net::HTTP::Post) }

  before(:each) do
    allow(Puppet).to receive(:initialize_settings)
    allow(Puppet).to receive(:settings).and_return(certname: 'primary.example.com',
                                                    hostcert: '/etc/puppetlabs/puppet/ssl/certs/primary.pem',
                                                    hostprivkey: '/etc/puppetlabs/puppet/ssl/private_keys/primary.pem',
                                                    localcacert: '/etc/puppetlabs/puppet/ssl/certs/ca.pem')
    allow(File).to receive(:read).and_return('dummy-pem-contents')
    allow(OpenSSL::X509::Certificate).to receive(:new).and_return(instance_double(OpenSSL::X509::Certificate))
    allow(OpenSSL::PKey::RSA).to receive(:new).and_return(instance_double(OpenSSL::PKey::RSA))

    allow(Net::HTTP).to receive(:new).with('primary.example.com', 4433).and_return(https_dbl)
    allow(https_dbl).to receive(:use_ssl=)
    allow(https_dbl).to receive(:cert=)
    allow(https_dbl).to receive(:key=)
    allow(https_dbl).to receive(:verify_mode=)
    allow(https_dbl).to receive(:ca_file=)

    allow(Net::HTTP::Post).to receive(:new).with('/rbac-api/v1/auth/token').and_return(request_dbl)
    allow(request_dbl).to receive(:[]=)
    allow(request_dbl).to receive(:body=)
  end

  # Catches a mutation that swaps/drops a field (login, password, lifetime,
  # or label) when building the token request body, which would send the
  # wrong credentials or request parameters to the RBAC API.
  it 'builds the POST body with login, password, lifetime, and label derived from the params' do
    expect(request_dbl).to receive(:body=) do |body|
      expect(JSON.parse(body)).to eq(
        'login'    => 'admin',
        'password' => 'supersecret',
        'lifetime' => '1y',
        'label'    => 'provision-time token',
      )
    end
    success_response = instance_double(Net::HTTPOK, body: { 'token' => 'abc123' }.to_json)
    allow(success_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
    allow(https_dbl).to receive(:request).with(request_dbl).and_return(success_response)
    allow(FileUtils).to receive(:mkdir_p)
    file_dbl = instance_double(File, write: nil)
    allow(File).to receive(:open).with('/root/.puppetlabs/token', 'w').and_yield(file_dbl)

    rbac_token.execute!
  end

  # Catches a mutation that drops the `unless response.is_a? Net::HTTPSuccess`
  # guard (or the response body from the error message), which would hide a
  # failed token request instead of raising a clear error.
  it 'raises with the response body when the RBAC API responds with a non-success status' do
    failure_response = instance_double(Net::HTTPUnauthorized, code: '401', body: '{"kind":"unauthorized","msg":"bad password"}')
    allow(failure_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
    allow(https_dbl).to receive(:request).with(request_dbl).and_return(failure_response)

    expect { rbac_token.execute! }.to raise_error(RuntimeError, 'Error requesting token (HTTP 401), {"kind":"unauthorized","msg":"bad password"}')
  end

  def stub_response(code, body: "{\"msg\":\"http #{code}\"}")
    response = instance_double(Net::HTTPResponse, code: code.to_s, body: body)
    allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
    allow(https_dbl).to receive(:request).with(request_dbl).and_return(response)
  end

  # PE-47009: callers' retry loops need to tell a permanent misconfiguration
  # (wrong password, malformed request) from a transient rbac-service
  # failure. Catches a mutation that widens/narrows the permanent set (e.g.
  # treating 500 as permanent would stop the PE-46689/PE-44867 retries).
  [400, 401].each do |code|
    it "raises RbacToken::AuthFailure for a permanent HTTP #{code}" do
      stub_response(code)

      expect { rbac_token.execute! }.to raise_error(RbacToken::AuthFailure, %(Error requesting token (HTTP #{code}), {"msg":"http #{code}"}))
    end
  end

  # A 400/401 whose body rbac-service itself labels a server error is a failure
  # on its side (e.g. warm-up), not a bad request, so it must stay retryable.
  # Without this the permanent set would turn a warm-up 401 into an immediate
  # install failure.
  [400, 401].each do |code|
    it "does not raise AuthFailure for HTTP #{code} when the body is a server-error" do
      stub_response(code, body: '{"kind":"puppetlabs.rbac/server-error","msg":"User admin failed to login"}')

      expect { rbac_token.execute! }.to raise_error(RuntimeError) { |e| expect(e).not_to be_a(RbacToken::AuthFailure) }
    end
  end

  it 'still raises AuthFailure for a 401 whose body is a different rbac kind' do
    stub_response(401, body: '{"kind":"puppetlabs.rbac/user-unauthenticated","msg":"bad password"}')

    expect { rbac_token.execute! }.to raise_error(RbacToken::AuthFailure)
  end

  it 'still raises AuthFailure for a 401 whose body is not JSON' do
    stub_response(401, body: 'Unauthorized')

    expect { rbac_token.execute! }.to raise_error(RbacToken::AuthFailure)
  end

  # Only a JSON object can carry a kind; every other body must fall back to the
  # status code (null/true/false once raised NoMethodError out of the helper,
  # which hid the real error and made the failure retryable).
  ['null', 'true', 'false', '1.5', '"a string"', '["not","an","object"]', ''].each do |body|
    it "still raises AuthFailure, with the HTTP status in the message, for a 401 whose body is #{body.inspect}" do
      stub_response(401, body: body)

      expect { rbac_token.execute! }.to raise_error(RbacToken::AuthFailure, %r{\AError requesting token \(HTTP 401\)})
    end
  end

  it 'only treats a kind that ends in server-error as one' do
    stub_response(401, body: '{"kind":"puppetlabs.rbac/server-error-detail"}')

    expect { rbac_token.execute! }.to raise_error(RbacToken::AuthFailure)
  end

  # 403 is retried on purpose: we can't rule out that rbac-service returns it
  # transiently during warm-up (see PERMANENT_STATUS_CODES).
  [403, 404, 408, 429, 500, 502, 503].each do |code|
    it "does not raise AuthFailure for a retryable HTTP #{code}" do
      stub_response(code)

      expect { rbac_token.execute! }.to raise_error(RuntimeError) { |e| expect(e).not_to be_a(RbacToken::AuthFailure) }
    end
  end

  describe '#run!' do
    it 'emits a Bolt _error with the peadm/rbac-auth-failure kind and exits 1 on a permanent failure' do
      stub_response(401)

      expect { rbac_token.run! }.to output(
        { '_error' => { 'msg' => 'Error requesting token (HTTP 401), {"msg":"http 401"}', 'kind' => 'peadm/rbac-auth-failure' } }.to_json + "\n",
      ).to_stdout.and raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end

    # Net::HTTP returns bodies binary-tagged, where String#scrub is a no-op,
    # so the body here is binary too -- not force_encoded to UTF-8.
    it 'scrubs invalid UTF-8 from the message so the permanent failure is still reported as such' do
      stub_response(401, body: "bad \xFF password".b)

      expect { rbac_token.run! }.to output(%r{"msg":"Error requesting token \(HTTP 401\), bad \uFFFD password".*"kind":"peadm/rbac-auth-failure"}).to_stdout.and raise_error(SystemExit)
    end

    it 'lets a connection error propagate as a generic error' do
      allow(https_dbl).to receive(:request).with(request_dbl).and_raise(Errno::ECONNREFUSED)

      expect { rbac_token.run! }.to raise_error(Errno::ECONNREFUSED)
    end

    it 'lets a transient failure propagate as a generic error' do
      stub_response(500)

      expect { rbac_token.run! }.to raise_error(RuntimeError, 'Error requesting token (HTTP 500), {"msg":"http 500"}')
    end
  end

  # Catches a mutation that writes the wrong content (e.g. the whole
  # response body instead of just the extracted token) or the wrong path,
  # which would leave a broken/garbage token file on disk.
  it 'extracts the token from the JSON response and writes only the token to /root/.puppetlabs/token' do
    success_response = instance_double(Net::HTTPOK, body: { 'token' => 'the-extracted-token' }.to_json)
    allow(success_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
    allow(https_dbl).to receive(:request).with(request_dbl).and_return(success_response)

    expect(FileUtils).to receive(:mkdir_p).with('/root/.puppetlabs')
    file_dbl = instance_double(File)
    expect(file_dbl).to receive(:write).with('the-extracted-token')
    expect(File).to receive(:open).with('/root/.puppetlabs/token', 'w').and_yield(file_dbl)

    rbac_token.execute!
  end

  # The spec suite sets RSPEC_UNIT_TEST_MODE, so the script's entry point is
  # never exercised; guard against it reverting to a bare execute!, which
  # would silently disable fail-fast.
  it 'runs the task through run! when executed as a script' do
    expect(IO.binread(File.expand_path('../../../tasks/rbac_token.rb', __dir__))).to match(%r{^\s*task\.run!$})
  end
end
