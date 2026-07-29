# Example solver stack

This directory contains a minimal, working example of the solver service
that `redmine_gtt_scheduler` talks to: [vroom-express][vroom-express] in
front of VROOM, with [OSRM][osrm] providing real road travel times.

It is an example to copy and adapt, not a production deployment. It has
no authentication and binds to localhost only.

## 1. Prepare the routing data (one time)

Download an extract for your region from [Geofabrik][geofabrik] and build
the OSRM graph. Japan is used here as an example; the extract is large
(several GB) and the build takes a while and needs plenty of RAM.

```bash
mkdir -p data && cd data
curl -O https://download.geofabrik.de/asia/japan-latest.osm.pbf
```

```bash
docker run -t -v "${PWD}:/data" ghcr.io/project-osrm/osrm-backend \
  osrm-extract -p /opt/car.lua /data/japan-latest.osm.pbf
```

```bash
docker run -t -v "${PWD}:/data" ghcr.io/project-osrm/osrm-backend \
  osrm-partition /data/japan-latest.osrm
```

```bash
docker run -t -v "${PWD}:/data" ghcr.io/project-osrm/osrm-backend \
  osrm-customize /data/japan-latest.osrm
```

For a first test, use a small extract instead (for example
`https://download.geofabrik.de/europe/germany/berlin-latest.osm.pbf`),
which builds in a couple of minutes.

## 2. Start the stack

Set `OSRM_BASENAME` to the extract name without the `.osrm` suffix:

```bash
OSRM_BASENAME=japan-latest docker compose up -d
```

## 3. Check it responds

```bash
curl -s -X POST http://localhost:3000 -H 'Content-Type: application/json' -d '{"vehicles":[{"id":1,"start":[139.7671,35.6812],"end":[139.7671,35.6812]}],"jobs":[{"id":1,"location":[139.7454,35.6586],"service":900}]}'
```

A `"code": 0` response with one route means the stack is working.

## 4. Point the plugin at it

In Redmine, go to Administration, Plugins, Redmine GTT Scheduler and set
the VROOM server URL. Use the compose service name (`http://vroom:3000`)
when Redmine runs in the same Docker network, or the host address
otherwise.

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

[vroom-express]: https://github.com/VROOM-Project/vroom-express
[osrm]: https://github.com/Project-OSRM/osrm-backend
[geofabrik]: https://download.geofabrik.de/
