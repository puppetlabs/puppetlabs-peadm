# frozen_string_literal: true

require 'spec_helper_acceptance'
# @summary: default test does nothing
def test_peadm
  # return unless os[:family] != 'windows'
  return unless os[:family] != 'Darwin'
end

describe 'default' do
  context 'example acceptance do nothing' do
    it do
      test_peadm
    end
  end
end
