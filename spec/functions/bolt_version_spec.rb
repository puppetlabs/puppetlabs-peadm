# frozen_string_literal: true

require 'spec_helper'
require 'bolt'

describe 'peadm::bolt_version' do

  it 'should_return_bolt_version' do
    is_expected.to run.and_return(Bolt::VERSION)
  end

end
