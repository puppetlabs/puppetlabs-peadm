# @summary This plan exists to account for a scenario where a PE XL
# architecture is in use, but code manager is not.
#
# The PE HA solution technically requires code manager be enabled and running.
# However, in unusual circumstances, it may not be possible for a customer to
# actually use code manager. This plan allows HA to be used by leaving
# file-sync turned on, but directing file-sync to deploy code to a
# non-standard, unused directory. This leaves the Puppet codedir available for
# management via an alternative means.
#
# This is a stop-gap at best. This should not be attempted without advisement.
#
plan pe_xl::misc::divert_code_manager (
  $master_host,
) {

  notice(@(HEREDOC))
    The code manager puppet-code live-dir will be diverted
      from: /etc/puppetlabs/code
      to:   /etc/puppetlabs/code-synchronized
    This will allow /etc/puppetlabs/code to be managed manually
    | HEREDOC

  run_task('pe_xl::divert_code_manager', $master_host)

  notice(@(HEREDOC))
    Remember to enforce this configuration in your Puppet code with a Collector Override. E.g.

      Pe_hocon_setting <| title == 'file-sync.repos.puppet-code.live-dir' |> {
        value => '/etc/puppetlabs/code-synchronized',
      }

    Remember also to disable static catalogs or configure static catalogs for
    use without file-sync. This can be done with a Hiera setting in pe.conf or
    the console:

      puppet_enterprise::master::static_catalogs: false

    Further documentation on static catalogs:
      https://puppet.com/docs/pe/2018.1/static_catalogs.html

    | HEREDOC

  return('Plan completed successfully')
}
