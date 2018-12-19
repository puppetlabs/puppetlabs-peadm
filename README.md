# Puppet Enterprise Extra Large

This Puppet module contains profile classes used to deploy an at-scale Puppet Enterprise architecture.

* This deployment depends on and assumes the use of trusted facts. Specifically, `pp_role` and `pp_environment`.
* This deployment assumes that at least for PE infrastructure nodes, Puppet certnames are correct, resolvable FQDNs.

Note: This is version *0.2.x* of the pe\_xl module. It is not compatible with version 0.1.x due to changes to role names.

## Documentation

See this README file and any documents in the [documentation](documentation) directory.

## Architecture

![architecture](documentation/images/architecture.png)

## Installation

These are just sketched out instructions right now. It's likely there are big gaps still.
