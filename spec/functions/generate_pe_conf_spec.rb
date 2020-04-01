require 'spec_helper'

describe 'peadm::generate_pe_conf' do
  let(:settings) do
    {'console_admin_password' => 'puppetlabs'}
  end
  let(:output) do 
    JSON.pretty_generate({
      "console_admin_password" => "puppetlabs",
      "puppet_enterprise::profile::console::java_args" => {
      "Xms" => "256m",
      "Xmx" => "768m"
      },
      "puppet_enterprise::profile::master::java_args" => {
      "Xms" => "512m",
      "Xmx" => "2048m"
      },
      "puppet_enterprise::profile::orchestrator::java_args" => {
      "Xms" => "256m",
      "Xmx" => "768m"
      },
      "puppet_enterprise::profile::puppetdb::java_args" => {
      "Xms" => "256m",
      "Xmx" => "768m"
      }
    })
  end
  
  it do 
    is_expected.to run.with_params(settings).and_return(/puppetlabs/) 
  end
end
