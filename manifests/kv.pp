class hoist::kv {
  assert_private()

  choria_kv_bucket{"HOIST":
    history    => 5,
    replicas   => $hoist::kv_replicas,
  }
}
