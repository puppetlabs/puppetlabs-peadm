# Puppet Enterprise Extra Large

This Puppet module contains Puppet Task Plans used to deploy an at-scale Puppet Enterprise architecture.

Use this module to deploy Puppet Enterprise 2019.0.x Extra Large architecture.

* This deployment depends on and assumes the use of trusted facts. Specifically, `pp_role` and `pp_environment`.
* This deployment assumes that at least for PE infrastructure nodes, Puppet certnames are correct, resolvable FQDNs.

## Documentation

See this README file and any documents in the [documentation](documentation) directory.

## Architecture

![architecture](documentation/images/architecture.png)
