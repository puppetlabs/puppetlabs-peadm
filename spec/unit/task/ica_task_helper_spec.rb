# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require_relative '../../../files/ica_task_helper'

describe IcaTaskHelper do
  before(:each) do
    allow(Puppet).to receive(:settings).and_return(
      certname: 'compiler-a.example.com',
      hostcert: '/not/a/real/file/hostcert.pem',
      hostprivkey: '/not/a/real/file/hostprivkey.pem',
      localcacert: '/not/a/real/file/ca.pem',
    )
  end

  describe '.bootstrap_cfg_path' do
    it 'resolves under puppetserver confdir' do
      expect(described_class.bootstrap_cfg_path).to eq('/etc/puppetlabs/puppetserver/bootstrap.cfg')
    end
  end

  describe '.ca_conf_path' do
    it 'resolves under puppetserver confdir' do
      expect(described_class.ca_conf_path).to eq('/etc/puppetlabs/puppetserver/conf.d/ca.conf')
    end
  end

  describe '.promoted_to_ica?' do
    it 'is false when bootstrap.cfg does not exist' do
      allow(File).to receive(:exist?).with(described_class.bootstrap_cfg_path).and_return(false)
      expect(described_class.promoted_to_ica?).to eq(false)
    end

    it 'is false when bootstrap.cfg exists but does not load IntermediateCAService' do
      allow(File).to receive(:exist?).with(described_class.bootstrap_cfg_path).and_return(true)
      allow(File).to receive(:readlines).with(described_class.bootstrap_cfg_path)
                                        .and_return(["puppetlabs.services.ca.certificate-authority-disabled-service/certificate-authority-disabled-service\n"])
      expect(described_class.promoted_to_ica?).to eq(false)
    end

    it 'is true when bootstrap.cfg loads IntermediateCAService' do
      allow(File).to receive(:exist?).with(described_class.bootstrap_cfg_path).and_return(true)
      allow(File).to receive(:readlines).with(described_class.bootstrap_cfg_path)
                                        .and_return(["puppetlabs.services.ca.intermediate-ca-service/intermediate-ca-service\n"])
      expect(described_class.promoted_to_ica?).to eq(true)
    end

    it 'is false when the only intermediate-ca-service line is commented out' do
      allow(File).to receive(:exist?).with(described_class.bootstrap_cfg_path).and_return(true)
      allow(File).to receive(:readlines).with(described_class.bootstrap_cfg_path).and_return(
        [
          "# puppetlabs.services.ca.intermediate-ca-service/intermediate-ca-service\n",
          "  #puppetlabs.services.ca.intermediate-ca-service/intermediate-ca-service\n",
          "puppetlabs.services.ca.certificate-authority-disabled-service/certificate-authority-disabled-service\n",
        ],
      )
      expect(described_class.promoted_to_ica?).to eq(false)
    end
  end

  describe '.active_service_line?' do
    it 'is true for an uncommented line naming the service' do
      expect(described_class.active_service_line?('puppetlabs.services.ca.intermediate-ca-service/intermediate-ca-service', 'intermediate-ca-service')).to eq(true)
    end

    it 'is false for a commented-out line naming the service' do
      expect(described_class.active_service_line?('  # puppetlabs.services.ca.intermediate-ca-service/intermediate-ca-service', 'intermediate-ca-service')).to eq(false)
    end

    it 'is false for a line naming a different service' do
      expect(described_class.active_service_line?('puppetlabs.services.ca.certificate-authority-service/certificate-authority-service', 'intermediate-ca-service')).to eq(false)
    end
  end

  describe '.run_ica_provision' do
    it 'shells out to the puppetserver ICA provisioning subcommand only' do
      status_dbl = instance_double('Process::Status', success?: true)
      expect(Open3).to receive(:capture3)
        .with(IcaTaskHelper::PUPPETSERVER_BIN, IcaTaskHelper::ICA_PROVISION_SUBCOMMAND)
        .and_return(['{"request-id":"abc"}', '', status_dbl])

      stdout, stderr, status = described_class.run_ica_provision
      expect(stdout).to eq('{"request-id":"abc"}')
      expect(stderr).to eq('')
      expect(status.success?).to eq(true)
    end
  end

  describe '.primary_https_client' do
    it 'builds an mTLS client using this node\'s agent certificate' do
      allow(File).to receive(:read).with('/not/a/real/file/hostcert.pem').and_return('cert-pem')
      allow(File).to receive(:read).with('/not/a/real/file/hostprivkey.pem').and_return('key-pem')
      fake_cert = instance_double('OpenSSL::X509::Certificate')
      fake_key = instance_double('OpenSSL::PKey::RSA')
      allow(OpenSSL::X509::Certificate).to receive(:new).with('cert-pem').and_return(fake_cert)
      allow(OpenSSL::PKey::RSA).to receive(:new).with('key-pem').and_return(fake_key)

      client = described_class.primary_https_client('primary.example.com')

      expect(client.address).to eq('primary.example.com')
      expect(client.port).to eq(8140)
      expect(client.use_ssl?).to eq(true)
      expect(client.cert).to eq(fake_cert)
      expect(client.key).to eq(fake_key)
      expect(client.verify_mode).to eq(OpenSSL::SSL::VERIFY_PEER)
      expect(client.ca_file).to eq('/not/a/real/file/ca.pem')
      expect(client.open_timeout).to eq(10)
      expect(client.read_timeout).to eq(30)
    end
  end

  describe '.pin_to_ica_group!' do
    let(:https) { instance_double('Net::HTTP') }
    let(:correct_classes) do
      {
        'puppet_enterprise::profile::master' => { 'pe_ca_ica_enabled' => true, 'enable_ca_proxy' => false },
        'puppet_enterprise::profile::compiler_ica_ca' => { 'ica_enabled' => true },
      }
    end

    it 'finds an existing, correctly-configured ICA group by name and pins the node to it, without reconciling' do
      groups_response = instance_double('Net::HTTPResponse', code: '200',
                                         body: [{ 'id' => 'group-1', 'name' => 'PE ICA Compilers', 'classes' => correct_classes }].to_json)
      expect(https).to receive(:get).with('/classifier-api/v1/groups').and_return(groups_response)

      pin_response = instance_double('Net::HTTPResponse', code: '204', body: '')
      expect(https).to receive(:request) do |req|
        expect(req.path).to eq('/classifier-api/v1/groups/group-1/pin')
        expect(JSON.parse(req.body)).to eq('nodes' => ['compiler-a.example.com'])
        pin_response
      end

      described_class.pin_to_ica_group!(https, 'compiler-a.example.com')
    end

    it "reconciles an existing group's classes before pinning, when they don't match" do
      # No 'classes' key at all here -- the same shape a group created by an
      # older or manually edited version of this task could carry.
      groups_response = instance_double('Net::HTTPResponse', code: '200',
                                         body: [{ 'id' => 'group-1', 'name' => 'PE ICA Compilers' }].to_json)
      expect(https).to receive(:get).with('/classifier-api/v1/groups').and_return(groups_response)

      reconcile_response = instance_double('Net::HTTPResponse', code: '200', body: '')
      expect(https).to receive(:request) { |req|
        expect(req.path).to eq('/classifier-api/v1/groups/group-1')
        expect(JSON.parse(req.body)).to eq('classes' => correct_classes)
        reconcile_response
      }.ordered

      pin_response = instance_double('Net::HTTPResponse', code: '204', body: '')
      expect(https).to receive(:request) { |req|
        expect(req.path).to eq('/classifier-api/v1/groups/group-1/pin')
        pin_response
      }.ordered

      described_class.pin_to_ica_group!(https, 'compiler-a.example.com')
    end

    it "reconciles an existing group's classes when they're present but only partially correct" do
      # This is the field scenario the reconciliation exists for: a group
      # that already has a 'classes' key, just missing or wrong on some of
      # the three required flags -- not the "classes absent entirely" case
      # covered above. Here compiler_ica_ca::ica_enabled is missing entirely.
      partial_classes = { 'puppet_enterprise::profile::master' => { 'pe_ca_ica_enabled' => true, 'enable_ca_proxy' => false } }
      groups_response = instance_double('Net::HTTPResponse', code: '200',
                                         body: [{ 'id' => 'group-1', 'name' => 'PE ICA Compilers', 'classes' => partial_classes }].to_json)
      expect(https).to receive(:get).with('/classifier-api/v1/groups').and_return(groups_response)

      reconcile_response = instance_double('Net::HTTPResponse', code: '200', body: '')
      expect(https).to receive(:request) { |req|
        expect(req.path).to eq('/classifier-api/v1/groups/group-1')
        expect(JSON.parse(req.body)).to eq('classes' => correct_classes)
        reconcile_response
      }.ordered

      pin_response = instance_double('Net::HTTPResponse', code: '204', body: '')
      expect(https).to receive(:request) { |req|
        expect(req.path).to eq('/classifier-api/v1/groups/group-1/pin')
        pin_response
      }.ordered

      described_class.pin_to_ica_group!(https, 'compiler-a.example.com')
    end

    it 'raises when reconciling an existing group fails' do
      groups_response = instance_double('Net::HTTPResponse', code: '200',
                                         body: [{ 'id' => 'group-1', 'name' => 'PE ICA Compilers' }].to_json)
      expect(https).to receive(:get).with('/classifier-api/v1/groups').and_return(groups_response)

      reconcile_response = instance_double('Net::HTTPResponse', code: '403', body: 'forbidden')
      expect(https).to receive(:request).and_return(reconcile_response)

      expect { described_class.pin_to_ica_group!(https, 'compiler-a.example.com') }
        .to raise_error(%r{Failed to reconcile classifier group group-1.*403.*forbidden})
    end

    it 'creates the ICA group when it does not yet exist, then pins' do
      groups_response = instance_double('Net::HTTPResponse', code: '200', body: [].to_json)
      expect(https).to receive(:get).with('/classifier-api/v1/groups').and_return(groups_response)

      create_response = instance_double('Net::HTTPResponse', code: '303', body: '',
                                         '[]' => '/classifier-api/v1/groups/group-2')
      expect(https).to receive(:request) { |req|
        expect(req.path).to eq('/classifier-api/v1/groups')
        body = JSON.parse(req.body)
        expect(body['name']).to eq('PE ICA Compilers')
        expect(body['parent']).to eq('00000000-0000-4000-8000-000000000000')
        master_params = body.dig('classes', 'puppet_enterprise::profile::master')
        # Both flags, or the catalog silently takes master.pp's earlier
        # `if $enable_ca_proxy` branch and never binds intermediate-ca-service.
        expect(master_params).to eq('pe_ca_ica_enabled' => true, 'enable_ca_proxy' => false)
        # Set in the same pin as the two above: profile::compiler_ica_ca
        # fails the catalog if master already binds intermediate-ca-service
        # while this is still false.
        ica_ca_params = body.dig('classes', 'puppet_enterprise::profile::compiler_ica_ca')
        expect(ica_ca_params).to eq('ica_enabled' => true)
        # The parameters are declared on profile::master, not the base class.
        expect(body['classes']).not_to have_key('puppet_enterprise')
        create_response
      }.ordered

      pin_response = instance_double('Net::HTTPResponse', code: '204', body: '')
      expect(https).to receive(:request) { |req|
        expect(req.path).to eq('/classifier-api/v1/groups/group-2/pin')
        pin_response
      }.ordered

      described_class.pin_to_ica_group!(https, 'compiler-a.example.com')
    end

    it 'raises with the response body when the classifier call fails' do
      groups_response = instance_double('Net::HTTPResponse', code: '500', body: 'boom')
      expect(https).to receive(:get).with('/classifier-api/v1/groups').and_return(groups_response)

      expect { described_class.pin_to_ica_group!(https, 'compiler-a.example.com') }
        .to raise_error(%r{Failed to fetch classifier groups.*boom})
    end

    it 'raises when the pin call returns a non-204 response' do
      groups_response = instance_double('Net::HTTPResponse', code: '200',
                                         body: [{ 'id' => 'group-1', 'name' => 'PE ICA Compilers', 'classes' => correct_classes }].to_json)
      expect(https).to receive(:get).with('/classifier-api/v1/groups').and_return(groups_response)

      pin_response = instance_double('Net::HTTPResponse', code: '403', body: 'forbidden')
      expect(https).to receive(:request).and_return(pin_response)

      expect { described_class.pin_to_ica_group!(https, 'compiler-a.example.com') }
        .to raise_error(%r{Failed to pin compiler-a\.example\.com to classifier group group-1.*403.*forbidden})
    end

    it 'falls through to group creation when the matched group has no id' do
      groups_response = instance_double('Net::HTTPResponse', code: '200',
                                         body: [{ 'name' => 'PE ICA Compilers' }].to_json)
      expect(https).to receive(:get).with('/classifier-api/v1/groups').and_return(groups_response)

      create_response = instance_double('Net::HTTPResponse', code: '303', body: '',
                                         '[]' => '/classifier-api/v1/groups/group-3')
      expect(https).to receive(:request) { |req|
        expect(req.path).to eq('/classifier-api/v1/groups')
        create_response
      }.ordered

      pin_response = instance_double('Net::HTTPResponse', code: '204', body: '')
      expect(https).to receive(:request) { |req|
        expect(req.path).to eq('/classifier-api/v1/groups/group-3/pin')
        pin_response
      }.ordered

      described_class.pin_to_ica_group!(https, 'compiler-a.example.com')
    end
  end

  describe '.find_ica_group_id' do
    let(:https) { instance_double('Net::HTTP') }

    it 'returns nil when the matched group is missing its id key' do
      groups_response = instance_double('Net::HTTPResponse', code: '200',
                                         body: [{ 'name' => 'PE ICA Compilers' }].to_json)
      expect(https).to receive(:get).with('/classifier-api/v1/groups').and_return(groups_response)

      expect(described_class.find_ica_group_id(https)).to be_nil
    end
  end

  describe '.create_ica_group!' do
    let(:https) { instance_double('Net::HTTP') }

    it 'raises when the classifier returns a non-303 response' do
      create_response = instance_double('Net::HTTPResponse', code: '500', body: 'kaboom')
      expect(https).to receive(:request).and_return(create_response)

      expect { described_class.create_ica_group!(https) }
        .to raise_error(%r{Failed to create classifier group PE ICA Compilers.*500.*kaboom})
    end

    it 'raises a clear error when a 303 response carries no Location header' do
      create_response = instance_double('Net::HTTPResponse', code: '303', body: '', '[]' => nil)
      expect(https).to receive(:request).and_return(create_response)

      expect { described_class.create_ica_group!(https) }
        .to raise_error(%r{303 but no Location header})
    end
  end
end
