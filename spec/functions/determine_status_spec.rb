# frozen_string_literal: true

require 'spec_helper'

describe 'peadm::determine_status' do
  let(:data) { JSON.parse(File.read(File.expand_path(File.join(fixtures, 'infrastatus.json')))) }
  let(:out) do
    JSON.parse(File.read(File.expand_path(File.join(fixtures, 'status.json'))))
  end

  it do
    is_expected.to run.with_params(data, false).and_return(out)
  end

  def svc(service, server, state = 'running')
    { 'service' => service, 'server' => server, 'state' => state }
  end

  it 'reports failed when no services are returned' do
    is_expected.to run.with_params([], false).and_return(
      'status' => 'failed', 'state' => {}, 'failed' => {}, 'passed' => {},
    )
  end

  it 'keeps a failed primary service that the replica also reports as running' do
    data = [svc('classifier-service', 'primary', 'unreachable'), svc('classifier-service', 'replica')]
    is_expected.to run.with_params(data, false).and_return(
      'status' => 'degraded',
      'state'  => { 'classifier-service/primary' => false, 'classifier-service/replica' => true },
      'failed' => { 'classifier-service/primary' => false },
      'passed' => { 'classifier-service/replica' => true },
    )
  end

  it 'fails a service reported more than once on the same server if any entry is not running' do
    # e.g. "PCP Broker" and "PCP Broker v2" are both reported as broker-service
    data = [svc('broker-service', 'primary', 'unreachable'), svc('broker-service', 'primary'), svc('pe-master', 'primary')]
    is_expected.to run.with_params(data, false).and_return(
      'status' => 'degraded',
      'state'  => { 'broker-service/primary' => false, 'pe-master/primary' => true },
      'failed' => { 'broker-service/primary' => false },
      'passed' => { 'pe-master/primary' => true },
    )
  end
end
