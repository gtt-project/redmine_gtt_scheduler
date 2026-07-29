# redmine_gtt_scheduler

VRP-based schedule optimization for location-based Redmine issues, part
of the [GTT Project](https://github.com/gtt-project).

Given issues with locations, time constraints, and a set of workers or
vehicles, the plugin computes who does what, in which order, and when,
using [VROOM](https://github.com/VROOM-Project/vroom) as the optimization
engine. Solved schedules are proposed first and only written back to the
issues after review.

## Status

v2 design phase. See [docs/design.md](docs/design.md) for the design
document. No installable release yet.

A first prototype was built here in 2022 during Google Summer of Code by
Ashish Kumar. v2 is a reboot with a different architecture (no core
schema changes, solver behind an HTTP adapter); the prototype remains
available in the git history.

## Planned architecture

- [redmine_gtt](https://github.com/gtt-project/redmine_gtt) provides
  issue geometry
- [redmine_issue_datetime](https://github.com/gtt-project/redmine_issue_datetime)
  provides time of day for start and due dates
- VROOM is reached over HTTP (vroom-express with OSRM for travel times),
  behind a small adapter interface so other backends can be added later

## License

GPL-3.0, see [LICENSE](LICENSE).
