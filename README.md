## Choria Container Hoist

This is a tiny container manager that uses [Choria Autonomous Agents](https://choria.io/docs/autoagents/), [Choria Key-Value Store](https://choria.io/docs/streams/key-value/) and [Choria Governor](https://choria.io/docs/streams/governor/) to manage a container.

The system downloads a container onto a node, starts it and checks it. Check failures are remediated by restarts. Restarts and updates can be initiated in an adhoc fasion.
Updates to a new version can be initiated via PUT to the Choria Key-Value store.

 * Supports running any docker container
 * Support customizing commands, entrypoints, ports, volumes and environment
 * Support rolling updates via Choria Key-Value store updates
 * Support no downtime updates and restarts by using a Choria Governor to limit concurrency
 * Support triggering container restarts by touching files on the host
 * Support for registering service ports into a service discovery store
 * Containers are actively managed, health checked, restarted and updated by the Choria daemon
 * Maintenance mode that pauses the container manager allowing manual intervention without the system interfering

You can think of this as a tiny k8s operator that manages one thing in isolation.  By joining these isolated containers on a Key-Value store for updates and a Governor
for roll out strategy management one can have declaritive real time container management in large clusters with regional or multi cluster update strategies.

## Usage

Include the main class on your machines:

```puppet
include hoist
```

Create Hiera data to configure containers and the hoist system.

## Hiera Data

|Item|Type|Description|
|----|----|-----------|
|hoist::purge|Boolean|When true (the default) unmanaged containers created by hoist will be removed|
|hoist::containers|Hash|Container definitions|

## Containers

Containers are created by Hiera, to remove a container just remove the data if `hoist::purge` is true.

### Basic

```yaml
hoist::containers:
  weather:
    image: example/weather
    image_tag: v1
    syslog: true
    environment:
      - WEATHER_API_KEY=c2..4a
    volumes:
      - /srv/weather/logs:/logs
    ports:
      - 8080:8080
```

This creates a basic container running `example/weather:v1` with ports and volumes.

### Key-Value based updates

You can use the Choria Key-Value store to manage this container, first we create a bucket to put data in.
Here I have a redundant Choria Broker cluster with 3 nodes so the KV bucket can be reliably distributed
and replicated across them.

```nohighlight
$ choria kv add HOIST --replicas 3
```

We can now instruct Hoist to watch the KV for updates:

```yaml
hoist::containers:
  weather:
    kv_update: true
    image: example/weather
    image_tag: v1
    syslog: true
    environment:
      - WEATHER_API_KEY=c2..4a
    volumes:
      - /srv/weather/logs:/logs
    ports:
      - 8080:8080
```

By adding the `kv_update: true` property Hoist will watch the bucket, if the bucket or key is not there
the `image_tag: v1` will be used as a default starting point.

Updating to the next version is then a matter of writing data to the KV:

```nohighlight
$ choria kv put HOIST container/weather/tag v2
```

The running instances will soon update to the `example/weather:v2` image. Use `choria scout watch` to view
the state changes in real time.

### Concurrency Control

Hoist can optionally control the concurrency of starts, restarts and updates meaning that if you have a number of
running containers and do an update via Puppet, Key-Value Store or Ad-Hoc management that only a certain number
of containers will go down at any given time.

To use this we create a governor:

```nohighlight
$ choria governor add HOIST_WEATHER 1 5m
```

This would allow 1 container in a group to be updates/restarted at the same time.

We can now tell Hoist to use this governor:

```yaml
hoist::containers:
  weather:
    restart_governor: HOIST_WEATHER
    update_governor: HOIST_WEATHER
    kv_update: true
    image: example/weather
    image_tag: v1
    syslog: true
    environment:
      - WEATHER_API_KEY=c2..4a
    volumes:
      - /srv/weather/logs:/logs
    ports:
      - 8080:8080
```

This combined with the Key-Value store or adhoc updates below can ensure that unattended updates do not
take the entire cluster down.

The `choria tool event` command will show a live view of the Governor to see how updates happen. Concurrency
can be adjusted using the `choria governor` command and updates will take effect immediately without changes
to the managed containers.

There are 2 governors that can be set, the `update_governor` will limit concurrent docker pulls while the `restart_governor`
will limit concurrent restarts.  It's safe to set them the same as here but the flexibility is there if needed.

### Port Registration

Containers that listen on ports can publish those ports to a Choria Key-Value bucket where other tools can
watch for those updates and configure systems like load balancers or reverse proxies:

```yaml
hoist::containers:
  surveyor:
    image: natsio/nats-surveyor
    image_tag: latest
    volumes:
      - /srv/nats/etc/system.cred:/system.cred
    command: "-s nats://n1.example.net:4222 --creds /system.cred -c 9 --accounts"
    ports:
      - 127.0.0.1:7777:7777/tcp
    register_ports:
      - cluster: "%{facts.location}"
        service: surveyor
        protocol: prometheus
        ip: "%{facts.networking.ip}"
        port: 7777
        priority: 1
        annotations:
          prometheus.io/scrape: "true"
          prometheus.io/path: /metrics
```

Here we publish the port `7777` using the, currently experimental, choria `gossip` watcher into a Key-Value store:

```
$ choria kv add --replicas 3 CHORIA_SERVICES --ttl 1m
$ choria kv keys CHORIA_SERVICES
lon.prometheus.surveyor.2ed769ea-37b6-49c4-aba4-b046440e8cf2
$ choria kv get CHORIA_SERVICES lon.prometheus.surveyor.2ed769ea-37b6-49c4-aba4-b046440e8cf2 --raw|jq
{
  "cluster": "lon",
  "service": "surveyor",
  "protocol": "prometheus",
  "address": "192.168.1.10",
  "port": 7777,
  "priority": 1,
  "annotations": {
    "prometheus.io/path": "/metrics",
    "prometheus.io/scrape": "true"
  }
}
```

The entries will be written every 15 seconds so here if the service has not been heard of for 4 cycles
it will vanish from the KV bucket.

This data can be read using a KV Watch to build related configuration files.

### Ad-Hoc management

One can interact with all or some of the weather service instances from the cli, here are some examples:

#### Status

Below we can see we have 9 instances of the service running, they are all in RUN state meaning they
are heatly and stable.

We have the following transitions available:

|Transition|Description|
|----------|-----------|
|stop      |Stops the container, moves to maintenance mode
|restart   |Restarts the container|
|update    |Fetches the latest image, if you set your tag to `latest` this will get the latest one and restart, else honors the kv tag|
|maintenace|Enter maintenance mode stopping health checks and remediation|

Once in maintenance mode the `resume` transition will put things back to normal.

```
$ choria req choria_util machine_state name=hoist_weather
...
n1-lon

   Available Transitions: ["stop", "restart", "update", "maintenance"]
                      ID: 063be722-2254-49c0-af88-437b17b96926
                    Name: hoist_weather
                    Path: /etc/choria/machine/hoist_weather
             Scout Check: false
                 Started: 1626255270
                   State: RUN
                 Version: 1.0.0
Summary of Name:

   hoist_weather: 9

Summary of State:

   RUN: 9

Summary of Version:

   1.0.0: 9
```

We can now transition to `update` which will fetch the latest version of the image and restart:

```
$ choria req choria_util machine_transition name=hoist_weather transition=update
Discovering nodes using the inventory method .... 9

9 / 9    0s [==============================================================================] 100%


Finished processing 9 / 9 hosts in 236ms
```

The service will immediately update.

## Contact

R.I.Pienaar / @ripienaar / rip@devco.net
