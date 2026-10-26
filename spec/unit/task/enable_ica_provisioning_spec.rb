# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../tasks/enable_ica_provisioning'

describe EnableIcaProvisioning do
  subject(:task) { described_class.new('primary_host' => 'primary.example.com') }

  let(:classifier_https) { instance_double('Net::HTTP') }

  before(:each) do
    allow(STDOUT).to receive(:puts)
    allow(Puppet).to receive(:settings).and_return(certname: 'compiler-a.example.com')
    allow(IcaTaskHelper).to receive(:primary_https_client).with('primary.example.com', IcaTaskHelper::CLASSIFIER_PORT).and_return(classifier_https)
    allow(IcaTaskHelper).to receive(:pin_to_ica_parent_group!)
  end

  describe '#execute!' do
    it "pins this compiler into the parent group, using the compiler's own certname, and reports pinned" do
      expect(IcaTaskHelper).to receive(:pin_to_ica_parent_group!).with(classifier_https, 'compiler-a.example.com')
      expect(STDOUT).to receive(:puts).with(JSON.generate('status' => 'pinned'))

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end

    it 'never pins into the child group, which is what binds IntermediateCAService' do
      expect(IcaTaskHelper).not_to receive(:pin_to_ica_group!)

      expect { task.execute! }.to raise_error(SystemExit)
    end

    it 'reports a failure through the _error contract and exits non-zero' do
      allow(IcaTaskHelper).to receive(:pin_to_ica_parent_group!).and_raise('classifier unavailable')
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['kind']).to eq('peadm/enable_ica_provisioning_failed')
        expect(parsed['_error']['msg']).to eq('classifier unavailable')
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end

    it 'logs the exception class and a backtrace to stderr on an unexpected failure' do
      allow(IcaTaskHelper).to receive(:pin_to_ica_parent_group!).and_raise(StandardError, 'boom')

      expect {
        begin
          task.execute!
        rescue SystemExit => e
          expect(e.status).to eq(1)
        end
      }.to output(%r{StandardError: boom}).to_stderr
    end
  end
end
