# frozen_string_literal: true

# rubocop:disable RSpec/BeforeAfterAll

require 'spec_helper'
# https://github.com/puppetlabs/bolt/blob/master/lib/bolt_spec/plans.rb

describe 'peadm::status' do
  # Include the BoltSpec library functions
  include BoltSpec::Plans

  # Configure Puppet and Bolt before running any tests
  before(:all) do
    BoltSpec::Plans.init
  end

  let(:infrastatus) do
    data = JSON.parse(File.read(File.expand_path(File.join(fixtures, 'infrastatus.json'))))
    { 'output' => data }
  end

  let(:summary) do
    File.read(File.expand_path(File.join(fixtures, 'plans', 'summary_table.txt')))
  end

  let(:failed) do
    File.read(File.expand_path(File.join(fixtures, 'plans', 'failed_table.txt')))
  end

  let(:passing) do
    File.read(File.expand_path(File.join(fixtures, 'plans', 'passed_table.txt')))
  end

  let(:raw_json_summary) do
    JSON.parse File.read(File.expand_path(File.join(fixtures, 'plans', 'raw_summary.json')))
  end

  let(:jsondata) do
    JSON.parse File.read(File.expand_path(File.join(fixtures, 'plans', 'summarized.json')))
  end

  it 'calls plan with table format' do
    allow_task('peadm::infrastatus').always_return(infrastatus)
    expect_out_message.with_params(failed)
    expect_out_message.with_params(summary)
    expect(run_plan('peadm::status', 'targets' => ['pnw_stack',
                                                   'east_stack', 'west_stack',
                                                   'northeast_stack'], 'format' => 'table')).to be_ok
  end

  it 'calls plan with verbose' do
    allow_task('peadm::infrastatus').always_return(infrastatus)
    expect_out_message.with_params(failed)
    expect_out_message.with_params(summary)
    expect_out_message.with_params(passing)
    expect(run_plan('peadm::status', 'targets' => ['pnw_stack',
                                                   'east_stack', 'west_stack', 'northeast_stack'],
                                     'format' => 'table', 'verbose' => true)).to be_ok
  end

  it 'calls plan with verbose and json' do
    allow_task('peadm::infrastatus').always_return(infrastatus)
    result = run_plan('peadm::status', 'targets' => ['pnw_stack',
                                                     'east_stack', 'west_stack',
                                                     'northeast_stack'], 'format' => 'json', 'verbose' => true, 'colors' => false)
    expect(result.value).to eq(jsondata)
  end

  it 'calls plan with verbose, json and raw output' do
    allow_task('peadm::infrastatus').always_return(infrastatus)
    result = run_plan('peadm::status', 'targets' => ['pnw_stack',
                                                     'east_stack', 'west_stack',
                                                     'northeast_stack'], 'format' => 'json', 'summarize' => false,
                                       'verbose' => true, 'colors' => false)
    expect(result.value).to eq(raw_json_summary)
  end
end
