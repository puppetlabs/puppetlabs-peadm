# spec/spec_helper.rb

# Load the BoltSpec library
require 'bolt_spec/plans'

describe 'peadm::util::retrieve_and_upload' do
  # Include the BoltSpec library functions
  include BoltSpec::Plans

  # Configure Puppet and Bolt before running any tests
  before(:each) do
    BoltSpec::Plans.init
  end

  it 'file needs downloaded and needs uploaded' do
    expect_command("test -e '/tmp/download'").error_with('kind' => 'nope', 'msg' => 'The command failed with exit code 1')
    expect_task('peadm::download')
    expect_task('peadm::filesize').be_called_times(2).return_for_targets(
      'local://localhost' => { 'size' => '2'},
      'primary' => { 'size' => 'null'}
    )
    expect_upload('/tmp/download').with_destination('/tmp/upload').with_params({}).return do |targets, source, destination, params|
      results = targets.map do |target|
        Bolt::Result.new(target, value: { 'path' => File.join(destination, source) })
      end
    
      Bolt::ResultSet.new(results)
    end
    
   expect(run_plan('peadm::util::retrieve_and_upload', 'nodes' => 'primary', 'source' => '/tmp/source', 'upload_path' => '/tmp/upload', 'local_path' => '/tmp/download')).to be_ok
  end
end
