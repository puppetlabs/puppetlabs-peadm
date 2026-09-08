require 'spec_helper'
require_relative '../../../tasks/classify_compilers'

describe ClassifyCompilers do
  subject(:task) { described_class.new(params) }

  let(:params) { { 'compiler_hosts' => ['compiler-a.example.com'] } }
  let(:success_status) { instance_double('Process::Status', success?: true) }
  let(:failure_status) { instance_double('Process::Status', success?: false) }

  before(:each) do
    allow(STDOUT).to receive(:puts)
  end

  describe '#classify_compiler' do
    # Catches a mutation that checks a different key/value (e.g. 'name'
    # instead of 'type') when looking for the puppetdb service.
    it 'returns :non_legacy when the services list includes a puppetdb service' do
      services = [{ 'type' => 'puppetdb' }, { 'type' => 'master' }]
      expect(task.classify_compiler(services)).to eq(:non_legacy)
    end

    # Catches a mutation that inverts the .any? predicate, which would
    # swap which compilers get flagged legacy vs modern -- the whole point
    # of this task.
    it 'returns :legacy when no service in the list is type puppetdb' do
      services = [{ 'type' => 'master' }]
      expect(task.classify_compiler(services)).to eq(:legacy)
    end
  end

  describe '#execute!' do
    # Catches a mutation that drops --host or --format=json, or mis-orders
    # the command, which would break the JSON.parse(stdout) call downstream.
    it 'runs `puppet infra status --host <name> --format=json` for the compiler host' do
      expect(Open3).to receive(:capture3)
        .with('puppet infra status --host compiler-a.example.com --format=json')
        .and_return([[{ 'type' => 'puppetdb' }].to_json, '', success_status])

      task.execute!
    end

    # Catches a mutation that puts a non-legacy compiler into
    # legacy_compilers instead of compilers.
    it 'places a compiler with a puppetdb service into compilers, not legacy_compilers' do
      allow(Open3).to receive(:capture3)
        .and_return([[{ 'type' => 'puppetdb' }].to_json, '', success_status])

      expect(STDOUT).to receive(:puts) do |json_str|
        expect(JSON.parse(json_str)).to eq('legacy_compilers' => [], 'compilers' => ['compiler-a.example.com'])
      end

      task.execute!
    end

    # Catches a mutation that swaps the two output keys' contents, or that
    # places a legacy compiler into the wrong list.
    it 'places a compiler with no puppetdb service into legacy_compilers, not compilers' do
      allow(Open3).to receive(:capture3)
        .and_return([[{ 'type' => 'master' }].to_json, '', success_status])

      expect(STDOUT).to receive(:puts) do |json_str|
        expect(JSON.parse(json_str)).to eq('legacy_compilers' => ['compiler-a.example.com'], 'compilers' => [])
      end

      task.execute!
    end

    # Catches a mutation that drops the `else` branch and silently ignores
    # command failures, which would make an unreachable compiler look like
    # it was simply never checked instead of erroring loudly.
    it 'excludes a host from both lists and writes a diagnostic to STDERR when the status command fails' do
      allow(Open3).to receive(:capture3).and_return(['', 'connection refused', failure_status])

      expect(STDERR).to receive(:puts).with('Error running command for compiler-a.example.com: connection refused')
      expect(STDOUT).to receive(:puts) do |json_str|
        expect(JSON.parse(json_str)).to eq('legacy_compilers' => [], 'compilers' => [])
      end

      task.execute!
    end

    # Pins a real gap (not fixed here, out of scope): JSON.parse(stdout) has
    # no rescue around it, so malformed output from one compiler crashes the
    # entire task run instead of failing just that host, unlike the
    # status.success? == false path above which is handled gracefully.
    it 'lets a JSON::ParserError from malformed stdout propagate uncaught, rather than failing just that host' do
      allow(Open3).to receive(:capture3).and_return(['not json', '', success_status])

      expect { task.execute! }.to raise_error(JSON::ParserError)
    end

    # Catches a mutation that only processes the first host, or that
    # classifies every host based on the last-seen result instead of each
    # host's own command output.
    it 'classifies multiple compiler hosts independently' do
      multi_params = { 'compiler_hosts' => ['compiler-a.example.com', 'compiler-b.example.com'] }
      multi_task = described_class.new(multi_params)
      allow(Open3).to receive(:capture3)
        .with('puppet infra status --host compiler-a.example.com --format=json')
        .and_return([[{ 'type' => 'puppetdb' }].to_json, '', success_status])
      allow(Open3).to receive(:capture3)
        .with('puppet infra status --host compiler-b.example.com --format=json')
        .and_return([[{ 'type' => 'master' }].to_json, '', success_status])

      expect(STDOUT).to receive(:puts) do |json_str|
        expect(JSON.parse(json_str)).to eq(
          'legacy_compilers' => ['compiler-b.example.com'],
          'compilers' => ['compiler-a.example.com'],
        )
      end

      multi_task.execute!
    end
  end
end
