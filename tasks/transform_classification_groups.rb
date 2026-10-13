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
    peinf = data.select { |x| x['name'] == 'PE Infrastructure' }
    group_id = peinf[0]['id']

    # Remove this group from the list and recursively remove all subgroups
    data.reject! { |x| x['id'] == group_id }
    data = removesubgroups(data, group_id)

    # Find the DR infrastructure group and its ID
    peinf_DR = data_DR.select { |x| x['name'] == 'PE Infrastructure' }
    id_DR = peinf_DR[0]['id']

    # Recursively go through inf groups to get the full tree
    peinf_DR = addsubgroups(data_DR, id_DR, peinf_DR)

    # Add the contents of the backup classification without PE inf to the DR PE inf groups
    # and write to a file
    peinf_transformed_groups = data + peinf_DR
    File.open(@transformed_classification_file, 'w') { |file| file.write(JSON.pretty_generate(peinf_transformed_groups)) }
  end

  private

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
  task.execute!
end
