# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'tmpdir'
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

  def groups_response(groups)
    instance_double('Net::HTTPResponse', code: '200', body: groups.to_json)
  end

  let(:infra_group) { { 'id' => 'infra-1', 'name' => 'PE Infrastructure' } }
  let(:parent_classes) { { 'puppet_enterprise::profile::compiler_ica_ca' => { 'ica_enabled' => true } } }
  let(:child_classes) { { 'puppet_enterprise::profile::master' => { 'pe_ca_ica_enabled' => true, 'enable_ca_proxy' => false } } }
  let(:pinned_rule) { ['or', ['=', 'name', 'compiler-a.example.com']] }
  let(:parent_group) do
    { 'id' => 'parent-1', 'name' => 'PE Intermediate CA', 'parent' => 'infra-1', 'classes' => parent_classes, 'rule' => pinned_rule }
  end

  describe '.pin_to_ica_parent_group!' do
    let(:https) { instance_double('Net::HTTP') }

    it 'creates the parent group under PE Infrastructure with only ica_enabled, then pins' do
      expect(https).to receive(:get).with('/classifier-api/v1/groups').and_return(groups_response([infra_group]))

      create_response = instance_double('Net::HTTPResponse', code: '303', body: '',
                                         '[]' => '/classifier-api/v1/groups/parent-9')
      expect(https).to receive(:request) { |req|
        expect(req.path).to eq('/classifier-api/v1/groups')
        body = JSON.parse(req.body)
        expect(body['name']).to eq('PE Intermediate CA')
        expect(body['parent']).to eq('infra-1')
        # Only the settings class: the master flags belong to the child group,
        # so pinning here can never bind IntermediateCAService.
        expect(body['classes']).to eq(parent_classes)
        create_response
      }.ordered

      pin_response = instance_double('Net::HTTPResponse', code: '204', body: '')
      expect(https).to receive(:request) { |req|
        expect(req.path).to eq('/classifier-api/v1/groups/parent-9/pin')
        expect(JSON.parse(req.body)).to eq('nodes' => ['compiler-a.example.com'])
        pin_response
      }.ordered

      described_class.pin_to_ica_parent_group!(https, 'compiler-a.example.com')
    end

    it 'pins to an existing, correctly configured parent group without reconciling' do
      expect(https).to receive(:get).and_return(groups_response([infra_group, parent_group]))
      pin_response = instance_double('Net::HTTPResponse', code: '204', body: '')
      expect(https).to receive(:request) { |req|
        expect(req.path).to eq('/classifier-api/v1/groups/parent-1/pin')
        pin_response
      }

      described_class.pin_to_ica_parent_group!(https, 'compiler-a.example.com')
    end

    it "reconciles an existing parent group's classes before pinning" do
      stale = parent_group.merge('classes' => {})
      expect(https).to receive(:get).and_return(groups_response([infra_group, stale]))

      reconcile_response = instance_double('Net::HTTPResponse', code: '200', body: '')
      expect(https).to receive(:request) { |req|
        expect(req.path).to eq('/classifier-api/v1/groups/parent-1')
        expect(JSON.parse(req.body)).to eq('classes' => parent_classes)
        reconcile_response
      }.ordered
      pin_response = instance_double('Net::HTTPResponse', code: '204', body: '')
      expect(https).to receive(:request) { |req|
        expect(req.path).to eq('/classifier-api/v1/groups/parent-1/pin')
        pin_response
      }.ordered

      described_class.pin_to_ica_parent_group!(https, 'compiler-a.example.com')
    end

    it 'refuses to touch a parent group that exists under an unexpected parent' do
      misplaced = parent_group.merge('parent' => '00000000-0000-4000-8000-000000000000')
      expect(https).to receive(:get).and_return(groups_response([infra_group, misplaced]))
      expect(https).not_to receive(:request)

      expect { described_class.pin_to_ica_parent_group!(https, 'compiler-a.example.com') }
        .to raise_error(%r{PE Intermediate CA already exists under a different parent})
    end

    it 'raises when PE Infrastructure is not present to parent the group' do
      expect(https).to receive(:get).and_return(groups_response([]))

      expect { described_class.pin_to_ica_parent_group!(https, 'compiler-a.example.com') }
        .to raise_error(%r{PE Infrastructure.*not found})
    end

    it 'raises when the pin call returns a non-204 response' do
      expect(https).to receive(:get).and_return(groups_response([infra_group, parent_group]))
      expect(https).to receive(:request).and_return(instance_double('Net::HTTPResponse', code: '403', body: 'forbidden'))

      expect { described_class.pin_to_ica_parent_group!(https, 'compiler-a.example.com') }
        .to raise_error(%r{Failed to pin compiler-a\.example\.com to classifier group parent-1.*403.*forbidden})
    end

    it 'raises with the response body when the classifier call fails' do
      expect(https).to receive(:get).and_return(instance_double('Net::HTTPResponse', code: '500', body: 'boom'))

      expect { described_class.pin_to_ica_parent_group!(https, 'compiler-a.example.com') }
        .to raise_error(%r{Failed to fetch classifier groups.*boom})
    end
  end

  describe '.pin_to_ica_group!' do
    let(:https) { instance_double('Net::HTTP') }
    let(:child_group) do
      { 'id' => 'child-1', 'name' => 'PE ICA Compilers', 'parent' => 'parent-1', 'classes' => child_classes }
    end

    it 'finds an existing, correctly configured child group and pins the node to it, without reconciling' do
      expect(https).to receive(:get).with('/classifier-api/v1/groups')
                                    .and_return(groups_response([infra_group, parent_group, child_group]))
      pin_response = instance_double('Net::HTTPResponse', code: '204', body: '')
      expect(https).to receive(:request) { |req|
        expect(req.path).to eq('/classifier-api/v1/groups/child-1/pin')
        expect(JSON.parse(req.body)).to eq('nodes' => ['compiler-a.example.com'])
        pin_response
      }

      described_class.pin_to_ica_group!(https, 'compiler-a.example.com')
    end

    it 'creates the child group under the parent with only the two master flags, then pins' do
      expect(https).to receive(:get).and_return(groups_response([infra_group, parent_group]))

      create_response = instance_double('Net::HTTPResponse', code: '303', body: '',
                                         '[]' => '/classifier-api/v1/groups/child-9')
      expect(https).to receive(:request) { |req|
        expect(req.path).to eq('/classifier-api/v1/groups')
        body = JSON.parse(req.body)
        expect(body['name']).to eq('PE ICA Compilers')
        expect(body['parent']).to eq('parent-1')
        # Both flags, or the catalog silently takes master.pp's earlier
        # `if $enable_ca_proxy` branch and never binds intermediate-ca-service.
        expect(body['classes']).to eq(child_classes)
        # ica_enabled is inherited from the parent, not repeated here.
        expect(body['classes']).not_to have_key('puppet_enterprise::profile::compiler_ica_ca')
        create_response
      }.ordered
      pin_response = instance_double('Net::HTTPResponse', code: '204', body: '')
      expect(https).to receive(:request) { |req|
        expect(req.path).to eq('/classifier-api/v1/groups/child-9/pin')
        pin_response
      }.ordered

      described_class.pin_to_ica_group!(https, 'compiler-a.example.com')
    end

    it "reconciles an existing child group's classes before pinning, when they don't match" do
      partial = child_group.merge('classes' => { 'puppet_enterprise::profile::master' => { 'pe_ca_ica_enabled' => true } })
      expect(https).to receive(:get).and_return(groups_response([infra_group, parent_group, partial]))

      reconcile_response = instance_double('Net::HTTPResponse', code: '200', body: '')
      expect(https).to receive(:request) { |req|
        expect(req.path).to eq('/classifier-api/v1/groups/child-1')
        expect(JSON.parse(req.body)).to eq('classes' => child_classes)
        reconcile_response
      }.ordered
      pin_response = instance_double('Net::HTTPResponse', code: '204', body: '')
      expect(https).to receive(:request) { |req|
        expect(req.path).to eq('/classifier-api/v1/groups/child-1/pin')
        pin_response
      }.ordered

      described_class.pin_to_ica_group!(https, 'compiler-a.example.com')
    end

    it 'raises when reconciling an existing child group fails' do
      stale = child_group.merge('classes' => {})
      expect(https).to receive(:get).and_return(groups_response([infra_group, parent_group, stale]))
      expect(https).to receive(:request).and_return(instance_double('Net::HTTPResponse', code: '403', body: 'forbidden'))

      expect { described_class.pin_to_ica_group!(https, 'compiler-a.example.com') }
        .to raise_error(%r{Failed to reconcile classifier group PE ICA Compilers.*403.*forbidden})
    end

    it 'refuses when the parent group does not exist, so ICA provisioning was never enabled' do
      expect(https).to receive(:get).and_return(groups_response([infra_group]))
      expect(https).not_to receive(:request)

      expect { described_class.pin_to_ica_group!(https, 'compiler-a.example.com') }
        .to raise_error(%r{PE Intermediate CA.*enable_ica_provisioning})
    end

    it 'refuses when the node is not pinned to the parent group, since it would never match the child' do
      unpinned = parent_group.merge('rule' => ['or', ['=', 'name', 'some-other-compiler.example.com']])
      expect(https).to receive(:get).and_return(groups_response([infra_group, unpinned]))
      expect(https).not_to receive(:request)

      expect { described_class.pin_to_ica_group!(https, 'compiler-a.example.com') }
        .to raise_error(%r{compiler-a\.example\.com is not pinned to PE Intermediate CA})
    end

    it 'refuses when the parent group has no rule at all' do
      ruleless = parent_group.reject { |k, _| k == 'rule' }
      expect(https).to receive(:get).and_return(groups_response([infra_group, ruleless]))

      expect { described_class.pin_to_ica_group!(https, 'compiler-a.example.com') }
        .to raise_error(%r{not pinned to PE Intermediate CA})
    end

    it 'refuses to touch a child group that exists under an unexpected parent' do
      misplaced = child_group.merge('parent' => '00000000-0000-4000-8000-000000000000')
      expect(https).to receive(:get).and_return(groups_response([infra_group, parent_group, misplaced]))
      expect(https).not_to receive(:request)

      expect { described_class.pin_to_ica_group!(https, 'compiler-a.example.com') }
        .to raise_error(%r{PE ICA Compilers already exists under a different parent})
    end

    it 'raises when the pin call returns a non-204 response' do
      expect(https).to receive(:get).and_return(groups_response([infra_group, parent_group, child_group]))
      expect(https).to receive(:request).and_return(instance_double('Net::HTTPResponse', code: '403', body: 'forbidden'))

      expect { described_class.pin_to_ica_group!(https, 'compiler-a.example.com') }
        .to raise_error(%r{Failed to pin compiler-a\.example\.com to classifier group child-1.*403.*forbidden})
    end

    it 'falls through to group creation when the matched child group has no id' do
      idless = { 'name' => 'PE ICA Compilers' }
      expect(https).to receive(:get).and_return(groups_response([infra_group, parent_group, idless]))

      create_response = instance_double('Net::HTTPResponse', code: '303', body: '',
                                         '[]' => '/classifier-api/v1/groups/child-3')
      expect(https).to receive(:request) { |req|
        expect(req.path).to eq('/classifier-api/v1/groups')
        create_response
      }.ordered
      pin_response = instance_double('Net::HTTPResponse', code: '204', body: '')
      expect(https).to receive(:request) { |req|
        expect(req.path).to eq('/classifier-api/v1/groups/child-3/pin')
        pin_response
      }.ordered

      described_class.pin_to_ica_group!(https, 'compiler-a.example.com')
    end
  end

  describe '.create_group!' do
    let(:https) { instance_double('Net::HTTP') }

    it 'raises when the classifier returns a non-303 response' do
      expect(https).to receive(:request).and_return(instance_double('Net::HTTPResponse', code: '500', body: 'kaboom'))

      expect { described_class.create_group!(https, 'PE ICA Compilers', 'parent-1', {}) }
        .to raise_error(%r{Failed to create classifier group PE ICA Compilers.*500.*kaboom})
    end

    it 'raises a clear error when a 303 response carries no Location header' do
      expect(https).to receive(:request).and_return(instance_double('Net::HTTPResponse', code: '303', body: '', '[]' => nil))

      expect { described_class.create_group!(https, 'PE ICA Compilers', 'parent-1', {}) }
        .to raise_error(%r{303 but no Location header})
    end
  end

  describe '.ca_conf_ica_settings' do
    let(:dir) { Dir.mktmpdir }
    let(:ca_conf) { File.join(dir, 'ca.conf') }

    after(:each) { FileUtils.remove_entry(dir) }

    before(:each) { allow(described_class).to receive(:ca_conf_path).and_return(ca_conf) }

    it 'is empty when ca.conf does not exist' do
      expect(described_class.ca_conf_ica_settings).to eq({})
    end

    it 'reads the three required ICA settings from an uncommented ca.conf' do
      File.write(ca_conf, <<~HOCON)
        certificate-authority: {
          ica-passphrase-path: "/etc/puppetlabs/puppetserver/ssl/ica_passphrase"
          ica-renewal-primary-url: "https://primary.example.com:8140"
          ica-renewal-root-ca-cert-path: "/etc/puppetlabs/puppet/ssl/certs/ca.pem"
        }
      HOCON

      expect(described_class.ca_conf_ica_settings).to eq(
        'ica-passphrase-path' => '/etc/puppetlabs/puppetserver/ssl/ica_passphrase',
        'ica-renewal-primary-url' => 'https://primary.example.com:8140',
        'ica-renewal-root-ca-cert-path' => '/etc/puppetlabs/puppet/ssl/certs/ca.pem',
      )
    end

    it 'does not count a commented-out setting' do
      File.write(ca_conf, %(certificate-authority: {\n  # ica-renewal-primary-url: "https://primary.example.com:8140"\n}\n))

      expect(described_class.ca_conf_ica_settings).to eq({})
    end
  end

  describe '.assert_provisioning_ready!' do
    let(:dir) { Dir.mktmpdir }
    let(:ca_conf) { File.join(dir, 'ca.conf') }
    let(:passphrase) { File.join(dir, 'ica_passphrase') }
    let(:full_ca_conf) do
      <<~HOCON
        certificate-authority: {
          ica-passphrase-path: "#{passphrase}"
          ica-renewal-primary-url: "https://primary.example.com:8140"
          ica-renewal-root-ca-cert-path: "/etc/puppetlabs/puppet/ssl/certs/ca.pem"
        }
      HOCON
    end

    after(:each) { FileUtils.remove_entry(dir) }

    before(:each) { allow(described_class).to receive(:ca_conf_path).and_return(ca_conf) }

    it 'passes when every ICA setting is present and the passphrase exists' do
      File.write(ca_conf, full_ca_conf)
      File.write(passphrase, 'secret')

      expect { described_class.assert_provisioning_ready! }.not_to raise_error
    end

    it 'names the missing settings and the stage that provides them' do
      File.write(ca_conf, %(certificate-authority: {\n  ica-passphrase-path: "#{passphrase}"\n}\n))
      File.write(passphrase, 'secret')

      expect { described_class.assert_provisioning_ready! }
        .to raise_error(%r{missing ica-renewal-primary-url, ica-renewal-root-ca-cert-path.*enable_ica_provisioning})
    end

    it 'raises when ca.conf does not exist' do
      expect { described_class.assert_provisioning_ready! }.to raise_error(%r{missing ica-passphrase-path})
    end

    it 'raises when the passphrase file has not been created, so the CSR was never submitted' do
      File.write(ca_conf, full_ca_conf)

      expect { described_class.assert_provisioning_ready! }
        .to raise_error(%r{No ICA passphrase at #{Regexp.escape(passphrase)}.*submit_ica_csr})
    end
  end
end
