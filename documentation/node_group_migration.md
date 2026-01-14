# Node Group Configuration Migration

## Overview

The node group configuration functionality in PEADM should be moved to the puppet-enterprise-modules repository as it is core PE infrastructure configuration, not PEADM-specific functionality.

## Current State

PEADM currently manages PE infrastructure node group classification through the following components:

### Files to be Moved

1. **`manifests/setup/node_manager.pp`**
   - Primary class that creates and configures all PE infrastructure node groups
   - Configures node groups for:
     - PE Infrastructure Agent
     - PE Master
     - PE Compiler
     - PE Database
     - PE Primary A/B (for DR architectures)
     - PE Compiler Group A/B
     - PE Legacy Compiler groups
   
2. **`manifests/setup/node_manager_yaml.pp`**
   - Helper class that sets up node_manager.yaml configuration
   - Required for node_group resources to work during Bolt apply runs

3. **`manifests/setup/convert_node_manager.pp`**
   - Migration helper for upgrading from PEADM 2.x to 3.x
   - Removes deprecated node groups

4. **`manifests/setup/legacy_compiler_group.pp`**
   - Manages legacy compiler node group configuration

5. **`templates/node_manager.yaml.epp`**
   - Template for node_manager.yaml configuration file

### Current Usage

These classes are currently called from:
- `plans/subplans/configure.pp` - Initial install configuration
- `plans/util/update_classification.pp` - Updating classification
- `plans/upgrade.pp` - PE upgrade process
- `plans/convert.pp` - Converting existing installations
- `plans/convert_compiler_to_legacy.pp` - Converting compilers

## Target State

Node group configuration should be handled by puppet-enterprise-modules, specifically:
- https://github.com/puppetlabs/puppet-enterprise-modules/tree/main/modules

### Proposed Approach

1. **Move Core Functionality**: The node group configuration logic should become part of PE's native installation and configuration process

2. **PEADM Integration**: PEADM should invoke PE's native classification configuration rather than managing it directly

3. **Deprecation Path**:
   - Mark current PEADM node group classes as deprecated
   - Document migration path for existing users
   - Provide compatibility layer during transition

## Benefits

Moving this functionality to puppet-enterprise-modules will:
1. Reduce duplication - PE classification should be managed by PE
2. Improve maintainability - PE team can maintain PE-specific configuration
3. Simplify PEADM - Focus on deployment orchestration, not PE internals
4. Better alignment - Classification configuration lives with PE code

## Implementation Notes

- The node group configuration uses the `node_group` resource type from puppetlabs-node_manager module
- Configuration is applied during Bolt apply runs with special node_manager.yaml setup
- Trusted facts (OIDs) are used for node group membership rules
- Configuration supports Standard, Large, and Extra-Large PE architectures

## Related Files

- Documentation: `documentation/classification.md`
- Tests: `spec/functions/get_node_group_environment_spec.rb`
- Functions: `functions/get_node_group_environment.pp`
