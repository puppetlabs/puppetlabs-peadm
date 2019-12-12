# Puppet Enterprise (pe) Administration (adm) Module

This Puppet module contains Puppet Task Plans used to deploy and manage at-scale Puppet Enterprise architecture.

Use this module to deploy Puppet Enterprise 2019.x Standard, Large, and Extra Large architecture.

* This deployment depends on and assumes the use of trusted facts. Specifically, `pp_application` and `pp_cluster`.
* This deployment assumes that at least for PE infrastructure nodes, Puppet certnames are correct, resolvable FQDNs.

## Documentation

See this README file and any documents in the [documentation](documentation) directory.

## Architecture

![architecture](documentation/images/architecture.png)
