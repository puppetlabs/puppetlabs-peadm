# @summary A PE release version with three numeric components and an optional suffix
type Peadm::Pe_version = Pattern[/^\d+\.\d+\.\d+(-.+)?$/]
