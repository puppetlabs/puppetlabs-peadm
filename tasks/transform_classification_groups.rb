#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

# rubocop:disable Naming/VariableName

# This script takes two classification outputs from source and target puppet infrastructure and
# takes the user definitions from the source and adds them to the infrastructure definitions of the
# target. This allows the ability to restore a backup of user node definitions.

require 'json'

# Class which merges a source cluster's user-defined classification groups
# into a target cluster's PE Infrastructure group tree, for DR restore.
class TransformClassificationGroups
  # Raised when the PE Infrastructure group can't be identified in a
  # classification, so run! can report it as a readable Bolt error.
  class InfraGroupNotFound < RuntimeError; end

  INFRA_GROUP_NOT_FOUND_KIND = 'peadm/infra-group-not-found'

  # All Nodes has this fixed id on every PE install.
  ALL_NODES_ID = '00000000-0000-4000-8000-000000000000'
  INFRA_GROUP_NAME = 'PE Infrastructure'

  def initialize(params)
    @source_classification_file      = "#{params['source_directory']}/classification_backup.json"
    @target_classification_file      = "#{params['working_directory']}/classification_backup.json"
    @transformed_classification_file = "#{params['working_directory']}/transformed_classification.json"
  end

  def execute!
    # Read the backup classification
    data = JSON.parse(File.read(@source_classification_file))

    # Read the DR server classification
    data_DR = JSON.parse(File.read(@target_classification_file))

    # Find the infrastructure group and its ID
    group_id = find_infra_group(data, "the source cluster's classification backup (#{@source_classification_file})")['id']

    # Remove this group from the list and recursively remove all subgroups
    data.reject! { |x| x['id'] == group_id }
    data = removesubgroups(data, group_id)

    # Find the DR infrastructure group and its ID
    infra_DR = find_infra_group(data_DR, "the target cluster's current classification (#{@target_classification_file})")
    id_DR = infra_DR['id']
    peinf_DR = [infra_DR]

    # Recursively go through inf groups to get the full tree
    peinf_DR = addsubgroups(data_DR, id_DR, peinf_DR)

    # Add the contents of the backup classification without PE inf to the DR PE inf groups
    # and write to a file
    peinf_transformed_groups = data + peinf_DR
    File.open(@transformed_classification_file, 'w') { |file| file.write(JSON.pretty_generate(peinf_transformed_groups)) }
  end

  # Runs the task, reporting a missing or ambiguous PE Infrastructure group
  # as a Bolt _error instead of a Ruby stack trace.
  def run!
    execute!
  rescue InfraGroupNotFound => e
    puts({ '_error' => { 'msg' => e.message, 'kind' => INFRA_GROUP_NOT_FOUND_KIND } }.to_json)
    exit 1
  end

  private

  # Finds the PE Infrastructure group without relying on its name, which
  # customers can change (PE-47659). It's the group directly under All Nodes
  # that carries the puppet_enterprise class; its id differs per install.
  # If more than one group matches, the one with the default name wins.
  # `where` names the classification being searched, for error messages.
  def find_infra_group(groups, where)
    candidates = groups.select do |g|
      g['parent'] == ALL_NODES_ID && (g['classes'] || {}).key?('puppet_enterprise')
    end
    return candidates.first if candidates.size == 1

    by_name = candidates.select { |g| g['name'] == INFRA_GROUP_NAME }
    return by_name.first if by_name.size == 1

    if candidates.empty?
      raise InfraGroupNotFound, "Could not find the PE Infrastructure node group in #{where}. " \
                                'PEADM looks for the node group directly under All Nodes that has the puppet_enterprise class; ' \
                                'its name does not matter, so a renamed group is fine. Check that this group exists ' \
                                'and still has the puppet_enterprise class, then retry.'
    end

    found = candidates.map { |g| "'#{g['name']}' (#{g['id']})" }.join(', ')
    raise InfraGroupNotFound, "Found more than one possible PE Infrastructure node group in #{where}: #{found}. " \
                              'Each is directly under All Nodes and has the puppet_enterprise class. Remove the ' \
                              "puppet_enterprise class from the groups that are not PE Infrastructure, or rename the real one to '#{INFRA_GROUP_NAME}', then retry."
  end

  # Recursively removes all subgroups (descendants) of the group identified
  # by id_rsg -- does not remove id_rsg's own entry, which the caller
  # must handle
  def removesubgroups(data_rsg, id_rsg)
    groups = data_rsg.select { |x| x['parent'] == id_rsg }
    groups.each do |group|
      subid = group['id']
      data_rsg.reject! { |x| x['id'] == subid }
      data_rsg = removesubgroups(data_rsg, subid)
    end
    data_rsg
  end

  # Recursively collects all subgroups (descendants) of the group
  # identified by id_asg into peinf_asg -- the caller seeds peinf_asg with
  # id_asg's own entry before calling, since this method only adds children
  def addsubgroups(data_asg, id_asg, peinf_asg)
    groups = data_asg.select { |x| x['parent'] == id_asg }
    peinf_asg += groups
    groups.each do |group|
      subid = group['id']
      peinf_asg = addsubgroups(data_asg, subid, peinf_asg)
    end
    peinf_asg
  end
end

# Run the task unless an environment flag has been set, signaling not to. The
# environment flag is used to disable auto-execution and enable Ruby unit
# testing of this task.
unless ENV['RSPEC_UNIT_TEST_MODE']
  task = TransformClassificationGroups.new(JSON.parse(STDIN.read))
  task.run!
end
