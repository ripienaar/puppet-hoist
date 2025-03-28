define hoist::container(
  String $image,
  String $image_tag = "latest",
  String $command = "",
  String $entrypoint = "",
  String $network = "bridge",
  Boolean $syslog = false,
  Boolean $kv_update = false,
  Integer $kv_interval = 60,
  String $restart_governor = "",
  String $update_governor = "",
  Array[Stdlib::Absolutepath] $restart_files = [],
  Array[String] $ports = [],
  Array[String] $volumes = [],
  Array[String] $environment = [],
  Array[Hash] $register_ports = [],
  Enum["present", "absent"] $ensure = "present",
) {
  if !("plugin.choria.machine.store" in $choria::server_config) {
    fail("Cannot configure choria::machine ${name}, plugin.choria.machine.store is not set")
  }

  $_store = $choria::server_config["plugin.choria.machine.store"]
  $_container_name = "hoist_${name}"

  file{
    default:
      before => File["${_store}/${_container_name}/machine.yaml"],
      owner  => "root",
      group  => "root";

    "${_store}/${_container_name}/env.sh":
      mode    => "0755",
      content => epp("hoist/env.epp", {"name" =>  $name, "kv" => $kv_update, "image" => $image, "tag" => $image_tag});

    "${_store}/${_container_name}/update.sh":
      mode    => "0755",
      content => epp("hoist/update.epp");

    "${_store}/${_container_name}/restart.sh":
      mode    => "0755",
      content => epp("hoist/restart.epp");

    "${_store}/${_container_name}/check.sh":
      mode    => "0755",
      content => epp("hoist/check.epp", {"name" => $name});

    "${_store}/${_container_name}/stop.sh":
      mode    => "0755",
      content => epp("hoist/stop.epp", {"name" => $name});

    "${_store}/${_container_name}/start.sh":
      mode              => "0755",
      content           => epp("hoist/start.epp", {
          "name"        => $_container_name,
          "command"     => $command,
          "entrypoint"  => $entrypoint,
          "network"     => $network,
          "syslog"      => $syslog,
          "ports"       => $ports,
          "volumes"     => $volumes,
          "environment" => $environment,
        }
      );
  }

  if $hoist::purge {
    file{"${_store}/hoist_purge/hoist_${name}.container":
      owner   => "root",
      group   => "root",
      content => "purge",
    }
  }

  $_transitions = [
    {
      "name"        => "maintenance",
      "destination" => "MAINTENANCE",
      "from"        => ["RUN", "START", "RESTART", "STOP", "UPDATE"],
    },
    {
      "name"        => "resume",
      "destination" => "RUN",
      "from"        => ["MAINTENANCE"],
    },
    {
      "name"        => "health_check",
      "destination" => "RUN",
      "from"        => ["START", "RESTART"],
    },
    {
      "name"        => "restart",
      "destination" => "RESTART",
      "from"        => ["RUN", "UPDATE"],
    },
    {
      "name"        => "update",
      "destination" => "UPDATE",
      "from"        => ["RUN", "RESTART", "START"],
    },
    {
      "name"        => "stop",
      "destination" => "STOP",
      "from"        => ["RUN", "RESTART", "START"],
    }
  ]

  $_restart_file_watchers = $restart_files.map |$file| {
    {
      "name"                   => "restart_on_${file}",
      "type"                   => "file",
      "success_transition"     => "restart",
      "state_match"            => ["RUN"],
      "properties"             => {
        "path"                 => $file,
        "gather_initial_state" => true,
      }
    }
  }

  if $kv_update and !$hoist::kv {
    fail("$hoist::kv should be true for KV enabled containers")
  }

  if $kv_update {
    $_kv_watcher = [{
      "name"               => "kv_tag",
      "type"               => "kv",
      "interval"           => "${kv_interval}s",
      "success_transition" => "update",
      "state_match"        => ["RUN", "RESTART", "START"],
      "properties"         => {
        "bucket"           => "HOIST",
        "key"              => "container/${name}/tag",
        "mode"             => "poll",
        "bucket_prefix"    => false
      }
    }]
  } else {
    $_kv_watcher =[]
  }

  if $update_governor != "" {
    $_update_governor = {"governor" => $update_governor}
  } else {
    $_update_governor = {}
  }

  if $restart_governor != "" {
    $_restart_governor = {"governor" => $restart_governor}
  } else {
    $_restart_governor = {}
  }

	if $register_ports.length > 0 {
		if $hoist::registration_interval >= 30 {
			$_interval = $hoist::registration_interval / 3
		} else {
			$_interval = 10
		}

		$_registration_watcher = $register_ports.map |$p| {
			{
				"name"           => sprintf("registration_%<protocol>s_%<port>s", $p),
				"type"           => "gossip",
				"interval"       => sprintf("%ds", $_interval),
				"state_match"    => ["RUN"],
				"properties"     => {
					"registration" => $p
				}
			}
		}
	} else {
		$_registration_watcher = {}
	}

  $_watchers = [
    {
      "name"                        => "check_running",
      "type"                        => "exec",
      "interval"                    => "20s",
      "fail_transition"             => "restart",
      "state_match"                 => ["RUN"],
      "properties"                  => {
        "command"                   => "./check.sh",
        "suppress_success_announce" => true,
        "timeout"                   => "60s"
      }
    },
    {
      "name"                        => "restart",
      "type"                        => "exec",
      "interval"                    => "15s",
      "success_transition"          => "health_check",
      "state_match"                 => ["RESTART"],
      "properties"                  => {
        "command"                   => "./restart.sh",
        "timeout"                   => "60s"
      } + $_restart_governor
    },
    {
      "name"                        => "stop_to_maintenance",
      "type"                        => "exec",
      "interval"                    => "20s",
      "success_transition"          => "maintenance",
      "state_match"                 => ["STOP"],
      "properties"                  => {
        "command"                   => "./stop.sh",
        "timeout"                   => "60s"
      }
    },
    {
      "name"                        => "pull_and_start",
      "type"                        => "exec",
      "interval"                    => "20s",
      "success_transition"          => "restart",
      "state_match"                 => ["UPDATE"],
      "properties"                  => {
        "command"                   => "./update.sh",
        "timeout"                   => "120s"
      } + $_update_governor
    },
    {
      "name"                   => "restart_on_start_sh_change",
      "type"                   => "file",
      "interval"               => "30s",
      "success_transition"     => "restart",
      "state_match"            => ["RUN"],
      "properties"             => {
        "path"                 => "./start.sh",
        "gather_initial_state" => true
      } + $_restart_governor
    }
  ] + $_kv_watcher + $_restart_file_watchers + $_registration_watcher

  choria::machine{"hoist_${name}":
    initial_state => "RUN",
    version       => "1.0.0",
    transitions   => $_transitions,
    watchers      => $_watchers,
  }
}
