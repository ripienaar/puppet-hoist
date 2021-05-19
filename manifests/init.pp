class hoist(
  Hash $containers = {},
  Boolean $purge = true
) {
  if $purge {
    include hoist::purge
  }

  $containers.each |$n, $c| {
    hoist::container{$n:
      * => $c
    }
  }
}
