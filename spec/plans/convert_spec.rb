# spec/spec_helper.rb

describe 'peadm::convert' do
  # Include the BoltSpec library functions
  include BoltSpec::Plans

  let(:trustedjson) do
    JSON.parse File.read(File.expand_path(File.join(fixtures, 'plans', 'trusted_facts.json')))
  end

it 'single primary no dr valid' do
  expect_out_message()
  expect_task('peadm::trusted_facts').return_for_targets(

    'primary' => trustedjson,
  )
  pending('a lack of support for functions requires a workaround to be written')
  expect_task('peadm::read_file').always_return({'content' => '2019.2.4'})
  expect_command('systemctl is-active puppet.service')
  expect_command('systemctl stop puppet.service')
  #expect_plan('peadm::util::add_cert_extensions')
  allow_apply()
  expect_task('peadm::cert_data')
  expect_task('peadm::puppet_runonce')
  expect(run_plan('peadm::convert', 'primary_host' => 'primary')).to be_ok
  end
end