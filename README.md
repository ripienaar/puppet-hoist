## Choria Container Hoist

This is a tiny container manager that uses [Choria Autonomous Agents](https://choria.io/docs/autoagents/) and [Choria Key-Value Store](https://choria.io/docs/streams/key-value/)
to manage a container.

The system downloads a container onto a node, starts it and checks it. Check failures are remediated by restarts. Restarts and updates can be initiated in an adhoc fasion.
Updates to a new version can be initiated via PUT to the Choria Key-Value store.

 * Supports running any docker container
 * Support customizing commands, entrypoints, ports, volumes and environment
 * Support rolling updates via Key-Value store updates
 * Containers are actively managed, health checked, restarted and updated by the Choria daemon
 * Maintenance mode that pauses the container manager allowing manual intervention without the system interfering

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

```nohighlight
$ choria kv add HOIST_weather
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
$ choria kv put HOIST_weather TAG v2
```

The running instances will soon update to the `example/weather:v2` image. Use `choria scout watch` to view
the state changes in real time.

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
$ choria req choria_util machine_state name=hoist
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
$ choria req choria_util machine_transition name=hoist_weather_v2 transition=update -C /nats/
Discovering nodes using the inventory method .... 9

9 / 9    0s [==============================================================================] 100%


Finished processing 9 / 9 hosts in 236ms
```

The service will immediately update.

## Planned features

 * Integration with [Choria Concurrency Governor](https://choria.io/docs/streams/governor/) for rolling updates without outages

## Contact

R.I.Pienaar / @ripienaar / rip@devco.net
