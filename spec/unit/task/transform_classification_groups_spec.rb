require 'spec_helper'
require_relative '../../../tasks/transform_classification_groups'

describe TransformClassificationGroups do
  subject(:task) { described_class.new(params) }

  let(:params) { { 'source_directory' => '/src', 'working_directory' => '/work' } }

  # Three levels deep on both source and target, so a mutation that only
  # handles direct children (not full recursion) would fail these.
  let(:source_groups) do
    [
      { 'id' => 'inf', 'parent' => 'root', 'name' => 'PE Infrastructure' },
      { 'id' => 'inf-child', 'parent' => 'inf', 'name' => 'PE Master' },
      { 'id' => 'inf-grandchild', 'parent' => 'inf-child', 'name' => 'PE Compiler' },
      { 'id' => 'custom', 'parent' => 'root', 'name' => 'My Custom Group' },
    ]
  end

  let(:target_groups) do
    [
      { 'id' => 'dr-inf', 'parent' => 'root', 'name' => 'PE Infrastructure' },
      { 'id' => 'dr-inf-child', 'parent' => 'dr-inf', 'name' => 'PE Master' },
      { 'id' => 'dr-inf-grandchild', 'parent' => 'dr-inf-child', 'name' => 'PE Compiler' },
    ]
  end

  let(:written_json) { [] }

  before(:each) do
    allow(File).to receive(:read).with('/src/classification_backup.json').and_return(source_groups.to_json)
    allow(File).to receive(:read).with('/work/classification_backup.json').and_return(target_groups.to_json)

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
      [{ 'id' => 'custom', 'parent' => 'root', 'name' => 'My Custom Group' }] +
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

  # Pins a real, pre-existing gap rather than fixing it: if the source
  # classification backup has no 'PE Infrastructure' group at all,
  # `peinf[0]['id']` indexes into an empty Array, giving nil, and `nil['id']`
  # raises a cryptic NoMethodError instead of a targeted, actionable message
  # (e.g. "Could not find 'PE Infrastructure' group in source classification
  # backup"). Unchanged by this ticket's structural-only refactor.
  it 'raises an unhelpful NoMethodError when the source has no PE Infrastructure group' do
    allow(File).to receive(:read).with('/src/classification_backup.json')
                                 .and_return([{ 'id' => 'custom', 'parent' => 'root', 'name' => 'My Custom Group' }].to_json)

    expect { task.execute! }.to raise_error(NoMethodError)
  end
end
