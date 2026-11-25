require 'spec_helper'
require_relative '../../../tasks/transform_classification_groups'

describe TransformClassificationGroups do
  subject(:task) { described_class.new(params) }

  let(:params) { { 'source_directory' => '/src', 'working_directory' => '/work' } }

  let(:all_nodes) { described_class::ALL_NODES_ID }
  let(:pe_classes) { { 'puppet_enterprise' => {} } }

  # Three levels deep on both source and target, so a mutation that only
  # handles direct children (not full recursion) would fail these.
  let(:source_groups) do
    [
      { 'id' => 'inf', 'parent' => all_nodes, 'name' => 'PE Infrastructure', 'classes' => pe_classes },
      { 'id' => 'inf-child', 'parent' => 'inf', 'name' => 'PE Master' },
      { 'id' => 'inf-grandchild', 'parent' => 'inf-child', 'name' => 'PE Compiler' },
      { 'id' => 'custom', 'parent' => all_nodes, 'name' => 'My Custom Group', 'classes' => {} },
    ]
  end

  let(:target_groups) do
    [
      { 'id' => 'dr-inf', 'parent' => all_nodes, 'name' => 'PE Infrastructure', 'classes' => pe_classes },
      { 'id' => 'dr-inf-child', 'parent' => 'dr-inf', 'name' => 'PE Master' },
      { 'id' => 'dr-inf-grandchild', 'parent' => 'dr-inf-child', 'name' => 'PE Compiler' },
    ]
  end

  let(:written_json) { [] }

  def written_ids
    JSON.parse(written_json.first).map { |g| g['id'] }
  end

  # Runs run! and returns [exit status, parsed _error] for a failing run.
  def run_and_capture_error
    status = nil
    out = StringIO.new
    previous_stdout = $stdout
    $stdout = out
    begin
      task.run!
    rescue SystemExit => e
      status = e.status
    ensure
      $stdout = previous_stdout
    end
    expect(status).to eq(1), "expected run! to exit 1, got #{status.inspect}; stdout: #{out.string.inspect}"
    [status, JSON.parse(out.string)['_error']]
  end

  before(:each) do
    # Serialized on each read (not up front), so examples can tweak
    # source_groups/target_groups before calling the task.
    allow(File).to receive(:read).with('/src/classification_backup.json') { source_groups.to_json }
    allow(File).to receive(:read).with('/work/classification_backup.json') { target_groups.to_json }

    file_dbl = instance_double(File)
    allow(File).to receive(:open).with('/work/transformed_classification.json', 'w').and_yield(file_dbl)
    allow(file_dbl).to receive(:write) { |content| written_json << content }
  end

  # Catches a mutation that only strips the PE Infrastructure group's
  # direct children (not deeper descendants), or that drops the
  # source-side PE Infrastructure group itself from the removal.
  it "strips the source's entire PE Infrastructure subtree (all levels), keeping its user-defined groups" do
    task.execute!

    written = JSON.parse(written_json.first)
    source_derived_ids = written.map { |g| g['id'] } & ['inf', 'inf-child', 'inf-grandchild', 'custom']

    expect(source_derived_ids).to eq(['custom'])
  end

  # Catches a mutation that only collects the target's PE Infrastructure
  # group's direct children (not deeper descendants), losing grandchild
  # groups from the restored tree.
  it "carries over the target's entire PE Infrastructure subtree (all levels)" do
    task.execute!

    written = JSON.parse(written_json.first)
    target_derived_ids = written.map { |g| g['id'] } & ['dr-inf', 'dr-inf-child', 'dr-inf-grandchild']

    expect(target_derived_ids).to contain_exactly('dr-inf', 'dr-inf-child', 'dr-inf-grandchild')
  end

  # Catches a mutation that writes reserialized/reordered JSON (e.g. via
  # .to_json instead of JSON.pretty_generate), or drops/duplicates groups,
  # by pinning the exact combined, pretty-printed output.
  it 'writes the source user groups plus the full target PE Infrastructure tree as pretty-printed JSON' do
    task.execute!

    expected = JSON.pretty_generate(
      [{ 'id' => 'custom', 'parent' => all_nodes, 'name' => 'My Custom Group', 'classes' => {} }] +
      target_groups,
    )
    expect(written_json.first).to eq(expected)
  end

  # Catches a mutation that hardcodes source_directory/working_directory
  # instead of interpolating the params, or that mixes up which directory
  # each file is read from/written to.
  context 'with different source_directory and working_directory params' do
    let(:params) { { 'source_directory' => '/other-src', 'working_directory' => '/other-work' } }

    it 'reads from and writes to the paths derived from those params' do
      # Explicitly reject the outer before(:each)'s /src and /work stubs:
      # without this, a mutation that hardcodes those paths instead of
      # interpolating source_directory/working_directory would still find
      # them stubbed and registered, and this test would pass anyway.
      expect(File).not_to receive(:read).with('/src/classification_backup.json')
      expect(File).not_to receive(:read).with('/work/classification_backup.json')
      expect(File).not_to receive(:open).with('/work/transformed_classification.json', 'w')

      allow(File).to receive(:read).with('/other-src/classification_backup.json').and_return(source_groups.to_json)
      allow(File).to receive(:read).with('/other-work/classification_backup.json').and_return(target_groups.to_json)
      file_dbl = instance_double(File)
      allow(File).to receive(:open).with('/other-work/transformed_classification.json', 'w').and_yield(file_dbl)
      allow(file_dbl).to receive(:write) { |content| written_json << content }

      expect { task.execute! }.not_to raise_error
      expect(written_json).not_to be_empty
    end
  end

  # PE-47659: customers can rename the PE Infrastructure group. It must be
  # found by its puppet_enterprise class under All Nodes, not by name, on
  # both the source and the target side.
  context 'when the PE Infrastructure group has been renamed' do
    it 'finds the renamed source group and still strips its whole subtree' do
      source_groups[0]['name'] = 'PE Infrastructure (renamed)'

      task.execute!

      written = JSON.parse(written_json.first)
      expect(written.map { |g| g['id'] }).to eq(['custom', 'dr-inf', 'dr-inf-child', 'dr-inf-grandchild'])
    end

    it 'finds the renamed target group and carries over its whole subtree' do
      target_groups[0]['name'] = 'PE Infra - PCI'

      task.execute!

      written = JSON.parse(written_json.first)
      expect(written.map { |g| g['id'] }).to eq(['custom', 'dr-inf', 'dr-inf-child', 'dr-inf-grandchild'])
    end
  end

  # A group named 'PE Infrastructure' that isn't the real one (wrong parent,
  # no puppet_enterprise class) must not be picked up as the infra group.
  it 'ignores a group that only has the PE Infrastructure name when finding the infra group' do
    source_groups[0]['name'] = 'Renamed infra'
    source_groups << { 'id' => 'decoy', 'parent' => 'custom', 'name' => 'PE Infrastructure', 'classes' => {} }
    # The target's infra group is renamed too, so the decoy doesn't clash
    # with it (that case is covered by the name-conflict examples below).
    target_groups[0]['name'] = 'Renamed infra'

    task.execute!

    expect(written_ids).to include('custom', 'decoy')
    expect(written_ids).not_to include('inf', 'inf-child', 'inf-grandchild')
  end

  # The classifier rejects two groups with the same name and environment
  # (422 uniqueness-violation), and import-hierarchy is all or nothing, so
  # writing such a file would lose every restored group (PE-47659 review).
  context 'when a kept source group has the same name and environment as a target PE Infrastructure group' do
    before(:each) do
      source_groups[0]['name'] = 'Renamed infra'
      source_groups << { 'id' => 'decoy', 'parent' => 'custom', 'name' => 'PE Infrastructure', 'classes' => {} }
    end

    it 'raises a name conflict naming the group, and writes nothing' do
      expect(File).not_to receive(:open)

      expect { task.execute! }.to raise_error(described_class::ClassificationNameConflict) { |e|
        expect(e.message).to include("'PE Infrastructure'")
        expect(e.message).to include('source group decoy')
        expect(e.message).to include('target group dr-inf')
      }
    end

    it 'allows the same name in a different environment' do
      source_groups.last['environment'] = 'development'
      target_groups[0]['environment'] = 'production'

      task.execute!

      expect(written_ids).to include('decoy', 'dr-inf')
    end

    it 'reports the conflict as a Bolt _error with its own kind' do
      expect(File).not_to receive(:open)
      _status, error = run_and_capture_error

      expect(error['kind']).to eq('peadm/classification-name-conflict')
      expect(error['msg']).to include("'PE Infrastructure'")
    end
  end

  # The All Nodes parent check: a nested group that has the puppet_enterprise
  # class is not a candidate, so it is neither picked nor makes the lookup
  # ambiguous.
  it 'does not pick, or count as ambiguous, a nested group with the puppet_enterprise class' do
    source_groups << { 'id' => 'nested-pe', 'parent' => 'custom', 'name' => 'Nested PE', 'classes' => pe_classes }
    source_groups[0]['name'] = 'Renamed infra'

    task.execute!

    expect(written_ids).to include('custom', 'nested-pe')
    expect(written_ids).not_to include('inf')
  end

  context 'when more than one top-level group carries the puppet_enterprise class' do
    let(:extra) { { 'id' => 'extra', 'parent' => all_nodes, 'name' => 'My PE Overrides', 'classes' => pe_classes } }

    it 'uses the one with the default name' do
      source_groups << extra

      task.execute!

      written = JSON.parse(written_json.first)
      expect(written.map { |g| g['id'] }).to include('custom', 'extra')
      expect(written.map { |g| g['id'] }).not_to include('inf')
    end

    it 'raises a clear error naming the candidates when none has the default name' do
      source_groups[0]['name'] = 'Renamed infra'
      source_groups << extra

      expect { task.execute! }.to raise_error(described_class::InfraGroupNotFound) { |e|
        expect(e.message).to include(
          "more than one possible PE Infrastructure node group in the source cluster's classification backup (/src/classification_backup.json): " \
          "'Renamed infra' (inf), 'My PE Overrides' (extra).",
        )
        expect(e.message).to include('Remove the puppet_enterprise class')
        expect(e.message).not_to include('then retry')
      }
    end
  end

  it 'raises a clear error when the source has no PE Infrastructure group, saying how to fix the backup' do
    allow(File).to receive(:read).with('/src/classification_backup.json')
                                 .and_return([{ 'id' => 'custom', 'parent' => all_nodes, 'name' => 'My Custom Group', 'classes' => {} }].to_json)
    expect(File).not_to receive(:open)

    expect { task.execute! }.to raise_error(described_class::InfraGroupNotFound) { |e|
      expect(e.message).to include(
        "Could not find the PE Infrastructure node group in the source cluster's classification backup (/src/classification_backup.json).",
      )
      expect(e.message).to include('directly under All Nodes that has the puppet_enterprise class')
      # migrate can't simply be retried: the new primary is already installed.
      expect(e.message).not_to include('then retry')
      expect(e.message).to include('take a new backup (peadm::backup backup_type=migration)')
      expect(e.message).to include("purge the old infrastructure nodes ('puppet node purge' on the new primary)")
      expect(e.message).to include('copy it to the new primary')
      # peadm::restore re-extracts the tarball, so editing the extracted file can't work.
      expect(e.message).not_to include('edit ')
    }
  end

  it 'raises a clear error when the target has no PE Infrastructure group, saying to fix it on the new primary' do
    target_groups[0]['classes'] = {}
    expect(File).not_to receive(:open)

    expect { task.execute! }.to raise_error(described_class::InfraGroupNotFound) { |e|
      expect(e.message).to include("in the target cluster's current classification (/work/classification_backup.json)")
      expect(e.message).not_to include('then retry')
      expect(e.message).to include('re-run peadm::restore restore_type=migration with the same backup')
      expect(e.message).to include('purge the old infrastructure nodes', 'add_database, add_replica and upgrade', "'puppet agent --enable' on the new hosts")
    }
  end

  # A classifier error body saved by backup_classification (401, 403, 500)
  # is not a list of groups and must not be reported as a missing group.
  context 'when a classification file is not a list of node groups' do
    it 'raises an invalid-classification error quoting the start of the file' do
      allow(File).to receive(:read).with('/work/classification_backup.json')
                                   .and_return({ 'kind' => 'puppetlabs.rbac/user-unauthenticated', 'msg' => 'Route requires authentication' }.to_json)
      expect(File).not_to receive(:open)

      expect { task.execute! }.to raise_error(described_class::InvalidClassification) { |e|
        expect(e.message).to include("the target cluster's current classification (/work/classification_backup.json)")
        expect(e.message).to include('is not a list of node groups')
        expect(e.message).to include('puppetlabs.rbac/user-unauthenticated')
      }
    end

    it 'raises an invalid-classification error for a file that is not JSON' do
      allow(File).to receive(:read).with('/src/classification_backup.json').and_return('<html>502 Bad Gateway</html>')
      expect(File).not_to receive(:open)

      expect { task.execute! }.to raise_error(described_class::InvalidClassification, %r{source cluster's classification backup.*not valid JSON.*502 Bad Gateway}m)
    end

    it 'reports it as a Bolt _error with its own kind' do
      allow(File).to receive(:read).with('/work/classification_backup.json').and_return([1, 2].to_json)

      _status, error = run_and_capture_error

      expect(error['kind']).to eq('peadm/invalid-classification')
      expect(error['msg']).to include('is not a list of node groups')
    end
  end

  describe '#run!' do
    it 'reports a missing PE Infrastructure group as a Bolt _error and exits 1, writing nothing' do
      target_groups[0]['classes'] = {}
      expect(File).not_to receive(:open)

      _status, error = run_and_capture_error

      expect(error['kind']).to eq('peadm/infra-group-not-found')
      expect(error['msg']).to include("Could not find the PE Infrastructure node group in the target cluster's current classification")
    end

    it 'writes the transformed file when the groups are found' do
      expect { task.run! }.not_to raise_error
      expect(written_json).not_to be_empty
    end
  end
end
