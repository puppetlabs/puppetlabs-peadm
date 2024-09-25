# Convert compilers to legacy

### Puppet Enterprise installed with puppetlabs-peadm version 3.25 or later

To convert compilers to legacy compilers use the `peadm::convert_compiler_to_legacy` plan. This plan will create the needed Node group and Classifier rules to make compilers legacy. Also will add certificate extensions to those nodes.

```shell
bolt plan run peadm::convert_compiler_to_legacy legacy_hosts=compiler1.example.com,compiler2.example.com primary_host=primary.example.com
```
