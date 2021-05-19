class hoist::purge {
  assert_private()

  if !("plugin.choria.machine.store" in $choria::server_config) {
    fail("Cannot configure choria::machine ${name}, plugin.choria.machine.store is not set")
  }

  if !$choria::purge_machines {
    fail("hoist::purge can only be used if choria.purge_machines is enabled")
  }

  $_store = $choria::server_config["plugin.choria.machine.store"]

  file{"${_store}/hoist_purge/purge.sh":
    owner   => "root",
    group   => "root",
    mode    => "0755",
    content => epp("hoist/purge.epp")
  }

  $_transitions = [
    {
      "name"        => "maintenance",
      "destination" => "MAINTENANCE",
      "from"        => ["PURGE"],
    },
    {
      "name"        => "resume",
      "destination" => "PURGE",
      "from"        => ["MAINTENANCE"],
    },
  ]

  $_watchers = [
    {
      "name"                        => "purge_hoist_containers",
      "type"                        => "exec",
      "interval"                    => "30s",
      "state_match"                 => ["PURGE"],
      "properties"                  => {
        "command"                   => "./purge.sh",
        "suppress_success_announce" => true,
        "timeout"                   => "30s"
      }
    },
  ]

  choria::machine{"hoist_purge":
    initial_state => "PURGE",
    version       => "1.0.0",
    transitions   => $_transitions,
    watchers      => $_watchers,
  }
}
