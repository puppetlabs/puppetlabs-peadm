# frozen_string_literal: true

require 'spec_helper'

describe 'peadm::pe_db_names' do
  # The databases every supported PE version has had for the life of this
  # function. Every other case is these plus whatever that release added.
  original = [
    'pe-activity',
    'pe-classifier',
    'pe-inventory',
    'pe-orchestrator',
    'pe-rbac',
  ]

  context 'PE versions older than 2023.8' do
    it 'returns only the original databases' do
      is_expected.to run.with_params('2021.7.9').and_return(original)
    end
  end

  context 'PE 2023.8 and later' do
    it 'adds the host-action-collector database' do
      is_expected.to run.with_params('2023.8.0').and_return(original + ['pe-hac'])
    end
  end

  context 'PE 2025.0 and later' do
    it 'adds the patching database' do
      is_expected.to run.with_params('2025.0.0').and_return(original + ['pe-hac', 'pe-patching'])
    end
  end

  context 'PE 2025.3 and later' do
    it 'adds the infra-assistant database' do
      is_expected.to run.with_params('2025.3.0').and_return(
        original + ['pe-hac', 'pe-patching', 'pe-infra-assistant'],
      )
    end
  end

  context 'PE 2025.6 and later' do
    it 'adds the workflow database' do
      is_expected.to run.with_params('2025.6.0').and_return(
        original + ['pe-hac', 'pe-patching', 'pe-infra-assistant', 'pe-workflow'],
      )
    end

    it 'still returns the 2025.6 set for the newest 2025.x release' do
      is_expected.to run.with_params('2025.11.0').and_return(
        original + ['pe-hac', 'pe-patching', 'pe-infra-assistant', 'pe-workflow'],
      )
    end
  end

  context 'PE 2026.0 and later' do
    it 'adds the code-manager database' do
      is_expected.to run.with_params('2026.0.0').and_return(
        original + ['pe-hac', 'pe-patching', 'pe-infra-assistant', 'pe-workflow', 'pe-code-manager'],
      )
    end

    # Every branch in this function is an open-ended SemVerRange, so a 2026.x
    # version satisfies '>= 2025.6.0' too. If the 2026 case is not matched
    # first, 2026 silently falls through to the 2025.6 set and this fails.
    it 'does not fall through to the 2025.6 set on a later 2026 release' do
      is_expected.to run.with_params('2026.4.0').and_return(
        original + ['pe-hac', 'pe-patching', 'pe-infra-assistant', 'pe-workflow', 'pe-code-manager'],
      )
    end

    it 'does not add the code-manager database to the release just before it' do
      is_expected.to run.with_params('2025.12.0').and_return(
        original + ['pe-hac', 'pe-patching', 'pe-infra-assistant', 'pe-workflow'],
      )
    end
  end
end
