#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

# rubocop:disable Naming/VariableName

# This script takes two classification outputs from source and target puppet infrastructure and
# takes the user definitions from the source and adds them to the infrastructure definitions of the
# target, so a migration restore (peadm::restore restore_type=migration) can bring the source
# cluster's user node groups onto a new primary.

require 'json'

# Class which merges a source cluster's user-defined classification groups
# into a target cluster's PE Infrastructure group tree, for a migration
# restore (peadm::restore restore_type=migration).
class TransformClassificationGroups
  # Errors run! reports as a readable Bolt _error with the class's KIND.
  class TransformError < RuntimeError; end

  # The PE Infrastructure group can't be identified in a classification.
  class InfraGroupNotFound < TransformError
    KIND = 'peadm/infra-group-not-found'
  end

  # A classification file is not a JSON list of node groups, e.g. a
  # classifier error body that backup_classification saved.
  class InvalidClassification < TransformError
    KIND = 'peadm/invalid-classification'
  end

  # A kept source group would share a name and environment with a target
  # PE Infrastructure group. The classifier rejects that (422
  # uniqueness-violation) and import-hierarchy is all or nothing.
  class ClassificationNameConflict < TransformError
    KIND = 'peadm/classification-name-conflict'
  end

  # All Nodes has this fixed id on every PE install.
  ALL_NODES_ID = '00000000-0000-4000-8000-000000000000'
  INFRA_GROUP_NAME = 'PE Infrastructure'

  def initialize(params)
    @source_classification_file      = "#{params['source_directory']}/classification_backup.json"
    @target_classification_file      = "#{params['working_directory']}/classification_backup.json"
    @transformed_classification_file = "#{params['working_directory']}/transformed_classification.json"
  end

  def execute!
    source_where = "the source cluster's classification backup (#{@source_classification_file})"
    target_where = "the target cluster's current classification (#{@target_classification_file})"
    # The new primary is already installed when this runs, so migrate can't
    # simply be retried, and peadm::restore re-extracts the backup tarball
    # (an edited classification_backup.json would be overwritten). Nothing
    # has been imported yet, so restoring again is safe; the migrate steps
    # after the restore then still have to be run.
    rest = 'then do the peadm::migrate steps that come after the restore: purge the old infrastructure nodes ' \
           "('puppet node purge' on the new primary), add_database, add_replica and upgrade as needed, " \
           "and 'puppet agent --enable' on the new hosts."
    source_fix = 'Fix it on the source primary, take a new backup (peadm::backup backup_type=migration), copy it to ' \
                 "the new primary, restore it with peadm::restore restore_type=migration, and #{rest}"
    target_fix = "Fix it on the new primary, re-run peadm::restore restore_type=migration with the same backup, and #{rest}"

    # Read the backup classification
    data = read_classification(@source_classification_file, source_where)

    # Read the target (new primary) classification
    data_DR = read_classification(@target_classification_file, target_where)

    # Find the infrastructure group, then remove it and all its subgroups
    group_id = find_infra_group(data, source_where, source_fix)['id']
    data.reject! { |x| x['id'] == group_id }
    data = removesubgroups(data, group_id)

    # Find the target infrastructure group and collect its whole tree
    infra_DR = find_infra_group(data_DR, target_where, target_fix)
    peinf_DR = addsubgroups(data_DR, infra_DR['id'], [infra_DR])

    check_name_conflicts(data, peinf_DR, source_fix)

    # Add the backup's user groups to the target's PE Infrastructure tree
    # and write to a file
    peinf_transformed_groups = data + peinf_DR
    File.open(@transformed_classification_file, 'w') { |file| file.write(JSON.pretty_generate(peinf_transformed_groups)) }
  end

  # Runs the task, reporting a transform error as a Bolt _error with its
  # kind instead of a Ruby stack trace. Nothing is written on an error.
  def run!
    execute!
  rescue TransformError => e
    puts({ '_error' => { 'msg' => e.message, 'kind' => e.class::KIND } }.to_json)
    exit 1
  end

  private

  # Reads a classification file saved by peadm::backup_classification and
  # checks it is a list of node groups. A classifier error body (401, 403,
  # 500) or a non-JSON response would otherwise surface as a missing PE
  # Infrastructure group. Raises InvalidClassification quoting its start.
  def read_classification(file, where)
    body = File.read(file)
    begin
      groups = JSON.parse(body)
    rescue JSON::ParserError
      raise InvalidClassification, "#{where} is not valid JSON, so it can't be a list of node groups. It starts: #{excerpt(body)}"
    end
    unless groups.is_a?(Array) && groups.all? { |g| g.is_a?(Hash) }
      raise InvalidClassification, "#{where} is not a list of node groups, so it may hold a classifier error instead of the " \
                                   "classification. It starts: #{excerpt(body)}"
    end
    groups
  end

  def excerpt(text)
    flat = text.to_s.gsub(%r{\s+}, ' ').strip
    (flat.length > 200) ? "#{flat[0, 200]}..." : flat
  end

  # Finds the PE Infrastructure group without relying on its name, which
  # customers can change (PE-47659). It's the group directly under All Nodes
  # that carries the puppet_enterprise class; its id differs per install.
  # If several groups match and exactly one has the default name, that one
  # is used (and the others reported on stderr). Raises InfraGroupNotFound
  # when no group matches, or when several match and not exactly one has the
  # default name. `where` names the classification searched and `fix` says
  # how to correct it, for error messages.
  def find_infra_group(groups, where, fix)
    candidates = groups.select do |g|
      g['parent'] == ALL_NODES_ID && (g['classes'] || {}).key?('puppet_enterprise')
    end
    return candidates.first if candidates.size == 1

    by_name = candidates.select { |g| g['name'] == INFRA_GROUP_NAME }
    if by_name.size == 1
      skipped = (candidates - by_name).map { |g| "'#{g['name']}' (#{g['id']})" }.join(', ')
      warn "Using '#{INFRA_GROUP_NAME}' (#{by_name.first['id']}) as the PE Infrastructure node group in #{where}; " \
           "also under All Nodes with the puppet_enterprise class, and not used: #{skipped}."
      return by_name.first
    end

    if candidates.empty?
      raise InfraGroupNotFound, "Could not find the PE Infrastructure node group in #{where}. " \
                                'PEADM looks for the node group directly under All Nodes that has the puppet_enterprise class; ' \
                                'its name does not matter, so a renamed group is fine. Check that this group exists ' \
                                "and still has the puppet_enterprise class. #{fix}"
    end

    found = candidates.map { |g| "'#{g['name']}' (#{g['id']})" }.join(', ')
    raise InfraGroupNotFound, "Found more than one possible PE Infrastructure node group in #{where}: #{found}. " \
                              'Each is directly under All Nodes and has the puppet_enterprise class. Remove the ' \
                              "puppet_enterprise class from the groups that are not PE Infrastructure, or rename the real one to '#{INFRA_GROUP_NAME}'. #{fix}"
  end

  # Raises ClassificationNameConflict if a kept source group has the same
  # name and environment as a group in the target PE Infrastructure tree.
  # This happens when the source's infra group was renamed and another group
  # took its name; the classifier would reject the whole import.
  def check_name_conflicts(kept_source, target_tree, fix)
    # Written for the agent Ruby of older PE releases (2.5), so no to_h with a
    # block (2.6) and no filter_map (2.7).
    target_by_key = target_tree.each_with_object({}) { |g, h| h[[g['name'], g['environment']]] = g }
    conflicts = kept_source.map { |g|
      clash = target_by_key[[g['name'], g['environment']]]
      "'#{g['name']}' (source group #{g['id']}, target group #{clash['id']})" if clash
    }.compact
    return if conflicts.empty?

    raise ClassificationNameConflict, 'The source cluster has node groups with the same name and environment as groups in the ' \
                                      "new primary's PE Infrastructure tree: #{conflicts.join(', ')}. The classifier rejects " \
                                      'duplicate names, so none of the groups would be restored. Rename the source groups. ' \
                                      "#{fix}"
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
