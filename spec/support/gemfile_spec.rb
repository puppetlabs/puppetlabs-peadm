# frozen_string_literal: true

require 'spec_helper'
require 'bundler'

RSpec.describe 'Gemfile.lock verification' do
  let(:parser) { Bundler::LockfileParser.new(Bundler.read_file(Bundler.default_lockfile)) }
  let(:private_source) { 'https://rubygems-puppetcore.puppet.com/' }
  let(:public_source) { 'https://rubygems.org/' }
  let(:auth_token_present?) { !ENV['PUPPET_FORGE_TOKEN'].nil? }

  # Helper method to get source remotes for a specific gem
  def get_gem_source_remotes(gem_name)
    spec = parser.specs.find { |s| s.name == gem_name }
    return [] unless spec

    source = spec.source
    return [] unless source.is_a?(Bundler::Source::Rubygems)

    source.remotes.map(&:to_s)
  end

  context 'when PUPPET_FORGE_TOKEN is present' do
    before(:each) do
      skip 'Skipping private source tests - PUPPET_FORGE_TOKEN not present' unless auth_token_present?
    end

    it 'has puppet under private source' do
      remotes = get_gem_source_remotes('puppet')
      expect(remotes).to eq([private_source]),
                         "Expected puppet to use private source #{private_source}, got: #{remotes.join(', ')}"
      expect(remotes).not_to eq([public_source]),
                             "Expected puppet to not use public source #{public_source}, got: #{remotes.join(', ')}"
    end

    it 'has facter under private source' do
      remotes = get_gem_source_remotes('facter')
      expect(remotes).to eq([private_source]),
                         "Expected facter to use private source #{private_source}, got: #{remotes.join(', ')}"
      expect(remotes).not_to eq([public_source]),
                             "Expected facter to not use public source #{public_source}, got: #{remotes.join(', ')}"
    end
  end

  context 'when PUPPET_FORGE_TOKEN is not present' do
    before(:each) do
      skip 'Skipping public source tests - PUPPET_FORGE_TOKEN is present' if auth_token_present?
    end

    it 'has puppet under public source' do
      remotes = get_gem_source_remotes('puppet')
      expect(remotes).to eq([public_source]),
                         "Expected puppet to use public source #{public_source}, got: #{remotes.join(', ')}"
      expect(remotes).not_to eq([private_source]),
                             "Expected puppet to not use private source #{private_source}, got: #{remotes.join(', ')}"
    end

    it 'has facter under public source' do
      remotes = get_gem_source_remotes('facter')
      expect(remotes).to eq([public_source]),
                         "Expected facter to use public source #{public_source}, got: #{remotes.join(', ')}"
      expect(remotes).not_to eq([private_source]),
                             "Expected facter to not use private source #{private_source}, got: #{remotes.join(', ')}"
    end
  end
end
