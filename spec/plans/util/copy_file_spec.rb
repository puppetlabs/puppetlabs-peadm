require 'spec_helper'

describe 'peadm::util::copy_file' do
  include BoltSpec::Plans

  let(:params) do
    {
      'targets'     => 'replica',
      'source_host' => 'primary',
      'path'        => '/etc/puppetlabs/enterprise/conf.d/pe.conf',
    }
  end

  it 'writes the source content to the targets' do
    expect_task('peadm::read_file').always_return('content' => "{}\n")
    expect_task('peadm::mkdir_p_file').with_params(
      'path' => params['path'], 'owner' => 'root', 'group' => 'root', 'mode' => '0644', 'content' => "{}\n",
    )

    expect(run_plan('peadm::util::copy_file', params)).to be_ok
  end

  it 'skips the copy when the source file is missing' do
    expect_task('peadm::read_file').always_return('content' => nil, 'error' => 'File does not exist or is not readable')
    expect_task('peadm::mkdir_p_file').not_be_called
    expect_out_message.with_params("Skipping file copy: #{params['path']} on primary had no content")

    expect(run_plan('peadm::util::copy_file', params)).to be_ok
  end

  # A read error must fail the plan, not be mistaken for a missing file and
  # skipped, or written out as an empty file.
  it 'fails, without writing anything, when the source file cannot be read' do
    expect_task('peadm::read_file').error_with(
      'kind' => 'peadm/read-file-error',
      'msg' => "Could not read #{params['path']}: 'utf-8' codec can't decode byte 0xff",
    )
    expect_task('peadm::mkdir_p_file').not_be_called

    result = run_plan('peadm::util::copy_file', params)

    expect(result).not_to be_ok
    expect(result.value.kind).to eq('bolt/run-failure')
    expect(result.value.details['result_set'].first.error.kind).to eq('peadm/read-file-error')
  end
end
