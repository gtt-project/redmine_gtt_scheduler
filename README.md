# redmine_gtt_scheduler

VRP-based schedule optimization for location-based Redmine issues, part
of the [GTT Project](https://github.com/gtt-project).

Given issues with locations, time constraints, and a set of workers or
vehicles, the plugin computes who does what, in which order, and when,
using [VROOM](https://github.com/VROOM-Project/vroom) as the optimization
engine. Solved schedules are proposed first and only written back to the
issues after review.

## Status

Early development, no release yet. Implemented and tested: resources,
optimization runs, the VROOM adapter, the propose-then-apply workflow,
per-resource route colours and toggles on the run map (with real road
geometry when the solver is asked for it), an hour-level timeline, and
locally derived diagnostics for unassigned issues, skills matching
(an issue requiring skills is only assigned to a resource that has all
of them), capacity limits (each issue's load counts against the
resource's capacity), per-resource working days, daily breaks,
multi-day planning (a run can cover a range of days, with one route per
resource per working day), and pickup/delivery pairs (two issues joined
by a configurable relation are served in order by the same resource).
Alternative solver backends
([#34](https://github.com/gtt-project/redmine_gtt_scheduler/issues/34))
are planned. See [docs/design.md](docs/design.md) for the design
document.

A first prototype was built here in 2022 during Google Summer of Code by
Ashish Kumar. v2 is a reboot with a different architecture (no core
schema changes, solver behind an HTTP adapter); the prototype remains
available in the git history.

## Requirements

- Redmine 6.0 or later (tested against Redmine 6.1 and 7.0, on Ruby 3.4
  and 4.0)
- [redmine_gtt](https://github.com/gtt-project/redmine_gtt) 7.0.0 or
  later (issue geometry, map rendering)
- [redmine_issue_datetime](https://github.com/gtt-project/redmine_issue_datetime)
  (time of day for start and due dates)
- A reachable [vroom-express](https://github.com/VROOM-Project/vroom-express)
  service with an OSRM backend; [contrib/vroom](contrib/vroom) contains a
  working example stack with setup instructions

## Installation

Install the two dependency plugins first, then this plugin:

```bash
cd /path/to/redmine/plugins
git clone https://github.com/gtt-project/redmine_gtt.git
git clone https://github.com/gtt-project/redmine_issue_datetime.git
git clone https://github.com/gtt-project/redmine_gtt_scheduler.git
cd /path/to/redmine
bundle exec rake redmine:plugins:migrate RAILS_ENV=production
```

Restart Redmine, then:

1. **Administration → Plugins → Redmine GTT Scheduler → Configure**: set
   the vroom-express URL (default `http://vroom:3000`), the default
   service time, the solver timeout, and whether to request road
   geometry.
2. **Administration → Plugins → Redmine Issue Datetime → Configure**:
   enable the trackers you plan to schedule, or applied schedules keep
   their dates but lose the times of day.
3. In the project: enable the **GTT Scheduler** module (and the GTT
   module for the map) under project settings, and grant the
   `View scheduler` / `Manage scheduler` permissions to the relevant
   roles.

Solving runs as an ActiveJob background job. Redmine's default inline
async adapter works out of the box; if you use a queue backend, make
sure a worker is running or runs will stay in "solving".

## How it works

1. A dispatcher picks a planning day (or a range of days), selects the
   resources to plan with, and starts a run. All open issues of the
   project that have a location are planned.
2. Issue time windows come from redmine_issue_datetime, service time
   from `estimated_hours` (with a configurable default), priority from
   the issue priority, and required skills and load from configurable
   issue custom fields.
3. The solver proposes a schedule. Nothing is written to the issues
   yet. Issues that could not be planned are listed with a locally
   derived reason (VROOM itself does not report one). The run page shows
   each resource's route on the map in its own colour, toggleable per
   resource, following the actual roads when geometry was requested,
   plus an hour-level timeline.
4. On apply, the start and due dates, the times, and the assignee are
   written to each issue and journalized. Runs can also be discarded
   without touching any issue.

## Architecture

The solver is reached over HTTP behind a small adapter interface
(`Scheduler::Adapter`), so other backends can be added later. The
default `VroomExpressAdapter` talks to vroom-express, which wraps VROOM
and OSRM for travel times. No PostgreSQL extension is required, which
keeps the plugin installable on any Redmine, including ones on managed
databases.

## License

GPL-3.0, see [LICENSE](LICENSE).
