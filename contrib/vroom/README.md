# Example solver stack

This directory contains a minimal, working example of the solver service
that `redmine_gtt_scheduler` talks to: [vroom-express][vroom-express] in
front of VROOM, with [OSRM][osrm] providing real road travel times.

It is an example to copy and adapt, not a production deployment. The API
is published on the Docker host's loopback address only, but it has no
authentication and is reachable from any container on the same network,
so put it behind your own access control before exposing it further.

Everything below has been run end to end; the timings are measured, not
estimated.

## 1. Prepare the routing data (one time)

Pick the **smallest [Geofabrik][geofabrik] extract that covers your
issues**, not the whole country. Geofabrik publishes sub-regions, and the
difference is large: `asia/japan/kansai` is 332 MiB against 2.3 GiB for
all of Japan, and the graph build scales with it.

Run these from this directory; each mounts `./data` into the container.
`data/` is gitignored, since the built graph is around 2 GB.

```bash
mkdir -p data && curl -L -o data/kansai-latest.osm.pbf https://download.geofabrik.de/asia/japan/kansai-latest.osm.pbf
```

```bash
docker run -t -v "${PWD}/data:/data" ghcr.io/project-osrm/osrm-backend:${OSRM_TAG:-v26.4.0} osrm-extract -p /opt/car.lua /data/kansai-latest.osm.pbf
```

```bash
docker run -t -v "${PWD}/data:/data" ghcr.io/project-osrm/osrm-backend:${OSRM_TAG:-v26.4.0} osrm-partition /data/kansai-latest.osrm
```

```bash
docker run -t -v "${PWD}/data:/data" ghcr.io/project-osrm/osrm-backend:${OSRM_TAG:-v26.4.0} osrm-customize /data/kansai-latest.osrm
```

For the Kansai extract on a laptop that is roughly two minutes for
`osrm-extract` (peak ~3.7 GB RAM), 15 seconds for `osrm-partition` and 6
seconds for `osrm-customize`, producing about 2 GB in `data/`.

### On the image tag

`v26.4.0` is the newest OSRM release published as a **multi-arch** image,
so the commands above work on both amd64 and arm64. Newer releases publish
architecture-suffixed tags only (`v26.7.3-arm64-debian`,
`v26.7.3-amd64-alpine`, ...). To use one, set `OSRM_TAG` to the tag
matching your host; a plain `v26.7.3` does not exist and fails with
`manifest unknown`.

## 2. Start the stack

From this directory, set `OSRM_BASENAME` to the extract name without the
`.osrm` suffix:

```bash
OSRM_BASENAME=kansai-latest docker compose up -d
```

OSRM's port 5000 is deliberately not published, only exposed inside the
compose network. That also avoids a clash on macOS, where AirPlay Receiver
listens on 5000 by default.

## 3. Check it responds

```bash
curl -s -X POST http://localhost:3100 -H 'Content-Type: application/json' -d '{"vehicles":[{"id":1,"start":[135.3550,34.7450],"end":[135.3550,34.7450]}],"jobs":[{"id":1,"location":[135.3600,34.7480],"service":900},{"id":2,"location":[135.3520,34.7420],"service":600}]}'
```

A `"code": 0` response with one route containing both jobs means the stack
is working. A `"duration"` above zero means OSRM is being consulted; if it
were unreachable the request would fail rather than return straight lines.

## 4. Point the plugin at it

In Redmine, go to Administration, Plugins, Redmine GTT Scheduler and set
the VROOM server URL. The default, `http://vroom:3000`, is correct when
Redmine shares this compose network. Use `http://localhost:3100` when
reaching it from the Docker host instead.

If Redmine already runs in its own compose project, attach the vroom
container to that network **with an alias**, or the hostname will not
resolve: a second network membership does not inherit the service-name
alias, only the container id.

```bash
docker network connect --alias vroom <redmine-network> <vroom-container>
```

## Notes

- The `car` profile is the only one wired up here. Per-resource profiles
  (bike, foot) are a later phase; adding them means building additional
  OSRM graphs and extending `conf/config.yml`.
- `maxlocations` in `conf/config.yml` caps how many stops one request may
  contain. Raise it if a single run plans more issues than the default
  1000.
- Rebuild the OSRM graph when you want newer map data. The graph files are
  read-only for the running container, so a rebuild plus a restart is
  enough.
- Issues outside the extract's area cannot be routed. Cover every location
  you plan with, or widen the extract.
- The plugin asks for route geometry with VROOM's `g` option so the run map
  can draw real roads. `conf/config.yml` already permits that per request
  via `override`; it can be switched off in the plugin's settings if the
  extra response size matters.

[vroom-express]: https://github.com/VROOM-Project/vroom-express
[osrm]: https://github.com/Project-OSRM/osrm-backend
[geofabrik]: https://download.geofabrik.de/
