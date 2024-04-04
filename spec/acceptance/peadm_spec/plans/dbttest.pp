plan peadm_spec::dbttest(
  TargetSpec $targets,
) {
  $t = get_target($targets)
  out::message('Running dbt test')
  out::message("targets: ${t}")
  out::message("config: ${t.config}")
  out::message("config: ${t.config['ssh']['user']}")
}
