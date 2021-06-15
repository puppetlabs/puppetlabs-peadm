# spec/spec_helper.rb

describe 'peadm::util::sanitize_pg_pe_conf ' do
  # Include the BoltSpec library functions
  include BoltSpec::Plans

  let(:pe_conf_json) do
    JSON.parse File.read(File.expand_path(File.join(fixtures, 'plans', 'pe_conf.json')))
  end

  it 'Runs' do
    #  1) peadm::util::sanitize_pg_pe_conf  Runs
    # Failure/Error: expect(run_plan('peadm::util::sanitize_pg_pe_conf', 'targets' => 'foo,bar', 'primary_host' => 'pe-server-d8b317-0.us-west1-a.c.davidsand.internal')).to be_ok
    # expected `#<Bolt::PlanResult:0x00007fd37d94b8a0 @value=#<Bolt::PAL::PALError: undefined method `start_with?' for #<Hash:0x00007fd36e30b350>>, @status="failure">.ok?` to be truthy, got false
    pending('a lack of support for functions requires a workaround to be written')
    expect_task('peadm::read_file').always_return('content' => pe_conf_json)
    expect(run_plan('peadm::util::sanitize_pg_pe_conf', 'targets' => 'foo,bar', 'primary_host' => 'pe-server-d8b317-0.us-west1-a.c.davidsand.internal')).to be_ok
  end
end
