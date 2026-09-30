# frozen_string_literal: true

require 'spec_helper'

describe 'peadm::availability_group_for' do
  let(:oid) { '1.3.6.1.4.1.34380.1.1.9813' }

  it 'assigns the default when there is no extensions hash for the certname' do
    is_expected.to run.with_params({}, 'primary', 'A').and_return('A')
  end

  it 'assigns the default when the certname has no availability group extension' do
    cert_extensions = { 'primary' => {} }
    is_expected.to run.with_params(cert_extensions, 'primary', 'A').and_return('A')
  end

  it 'assigns the default when certname is undef' do
    is_expected.to run.with_params({}, nil, 'A').and_return('A')
  end

  it 'preserves an existing "A" extension even when the default is "B"' do
    cert_extensions = { 'primary' => { oid => 'A' } }
    is_expected.to run.with_params(cert_extensions, 'primary', 'B').and_return('A')
  end

  it 'preserves an existing "B" extension even when the default is "A"' do
    cert_extensions = { 'replica' => { oid => 'B' } }
    is_expected.to run.with_params(cert_extensions, 'replica', 'A').and_return('B')
  end

  it 'falls back to the default when the existing extension value is neither "A" nor "B"' do
    cert_extensions = { 'primary' => { oid => 'garbage' } }
    is_expected.to run.with_params(cert_extensions, 'primary', 'A').and_return('A')
  end
end
