# redmine_gtt_scheduler

VRP-based schedule optimization for location-based Redmine issues, part
of the [GTT Project](https://github.com/gtt-project).

Given issues with locations, time constraints, and a set of workers or
vehicles, the plugin computes who does what, in which order, and when,
using [VROOM](https://github.com/VROOM-Project/vroom) as the optimization
engine. Solved schedules are proposed first and only written back to the
issues after review.

## Status

Early development, no release yet. Phase 1 is implemented: resources,
optimization runs, the VROOM adapter, and the propose-then-apply
workflow with a plain table UI. Map and timeline views, skills and
capacity, and pickup/delivery follow in later phases (see the
[issues](https://github.com/gtt-project/redmine_gtt_scheduler/issues)).
See [docs/design.md](docs/design.md) for the design document.

A first prototype was built here in 2022 during Google Summer of Code by
Ashish Kumar. v2 is a reboot with a different architecture (no core
schema changes, solver behind an HTTP adapter); the prototype remains
available in the git history.

## Architecture

- [redmine_gtt](https://github.com/gtt-project/redmine_gtt) provides
  issue geometry
- [redmine_issue_datetime](https://github.com/gtt-project/redmine_issue_datetime)
  provides time of day for start and due dates (hard dependency)
- VROOM is reached over HTTP (vroom-express with OSRM for travel times),
  behind a small adapter interface so other backends can be added later

## How it works

1. A dispatcher picks a planning day and starts a run. All open issues of
   the project that have a location are planned, using every active
   resource.
2. Issue time windows come from redmine_issue_datetime, service time from
   `estimated_hours`, and priority from the issue priority.
3. The solver proposes a schedule. Nothing is written to the issues yet;
   issues that could not be planned are listed with a reason. The run page
   shows each resource's route on the map, following the actual roads when
   the solver was asked for geometry, plus an hour-level timeline.
4. On apply, the start and due dates, the times, and the assignee are
   written to each issue and journalized.

## Requirements

- Redmine 6.0 or later
- redmine_gtt 7.0.0 or later, and redmine_issue_datetime
- A reachable vroom-express service; see
  [contrib/vroom](contrib/vroom) for a working example stack

## License

GPL-3.0, see [LICENSE](LICENSE).
