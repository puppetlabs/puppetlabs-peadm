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

  let(:source) { 'http://downloadsite.com/file' }
  let(:local_path) { '/tmp/download' }
  let(:upload_path) { '/tmp/upload' }
  let(:nodes) { 'ssh://root:letmein@localhost:22' }
  let(:targets) { 'localhost' }

  #it 'file is downloaded and uploaded' do
  #  expect_command("test -e '/tmp/download'").always_return({'stdout' => 'im here'})
  #  expect_task('peadm::download').not_be_called
  #  expect_task('peadm::filesize').always_return('size' => '1').be_called_times(2)
  #  allow_upload('/tmp/download')
  #  expect(run_plan('peadm::util::retrieve_and_upload', 'nodes' => 'host', 'source' => 'http://downloadsite.com/file', 'upload_path' => '/tmp/upload', 'local_path' => '/tmp/download')).to be_ok
  #end

  #it 'file needs downloaded and needs uploaded' do
  #  expect_command("test -e '/tmp/download'").error_with('kind' => 'nope', 'msg' => 'The command failed with exit code 1')
  #  expect_task('peadm::download')
  #  expect_task('peadm::filesize').be_called_times(2).return_for_targets(
  #    'local://localhost' => { 'size' => '2'},
  #    'localhost' => { 'size' => 'null'}
  #  )
  #  expect_upload('/tmp/download').return do |targets, source, upload_path |
  #    results = targets.map do |target|
  #    Bolt::Result.new(target, value: { 'path' => File.join(upload_path, source) })
  #    end
  #  Bolt::ResultSet.new(results)
  #  end
    
  #  expect(run_plan('peadm::util::retrieve_and_upload', 'nodes' => nodes, 'source' => source, 'upload_path' => upload_path, 'local_path' => local_path)).to be_ok
  #end

end
