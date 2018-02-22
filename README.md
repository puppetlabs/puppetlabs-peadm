# PE Architecture

This Puppet module contains profile classes used to deploy an at-scale Puppet Enterprise architecture.

It SHOULD contain instructions for how to set that all up, too. Right now it doesn't. Big To-do.

Note pending more detailed instructions:

* This deployment depends on and assumes the use of trusted facts. Specifically, `pp_role` and `pp_environment`.
* This deployment assumes that at least for PE infrastructure nodes, Puppet certnames are correct, resolvable FQDNs.
