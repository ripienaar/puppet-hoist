class hoist(
  Hash $containers = {},
  Boolean $purge = true,
  Boolean $kv = false,
  Boolean $manage_kv = false,
  Integer[1,5] $kv_replicas = 1,
  Boolean $registration = false,
  Integer[1,5] $registration_replicas = 1,
  Integer $registration_interval = 30,
) {
  if $purge and $choria::purge_machines {
    include hoist::purge
  }

  if $kv and $manage_kv {
    include hoist::kv
  }

  if $registration {
    include hoist::registration
  }

  $containers.each |$n, $c| {
    hoist::container{$n:
      * => $c
    }
  }
}
