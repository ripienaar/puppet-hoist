class hoist::registration {
  assert_private()

  choria_kv_bucket{"HOIST_REGISTRATION":
    history  => 1,
    expire   => $hoist::registration_interval,
    replicas => $hoist::registration_replicas,
  }
}
