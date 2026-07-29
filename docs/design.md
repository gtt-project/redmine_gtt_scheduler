# redmine_gtt_scheduler v2: Design Document

Status: Draft for review
Scope: VRP-based schedule optimization for location-based Redmine issues

## 1. Background

The goal is automatic schedule optimization for field work managed in
Redmine: given a set of issues with locations, time constraints, and a set
of workers/vehicles, compute who does what, in which order, and when.

A first prototype was built in this repository in 2022 (GSoC work by
Ashish Kumar, author of pg_scheduleserv). It proved the mapping from
Redmine data to VROOM concepts and remains valuable as a reference. v2 is
a reboot that keeps the problem framing but changes the architecture:

| v1 prototype | v2 |
| --- | --- |
| Changed `issues.start_date/due_date` to `datetime` via plugin migration | Never touches core schema; time of day comes from `redmine_issue_datetime` |
| Solver called in-database (`vrp_vroomPlain`, vrpRouting) | Solver behind an HTTP adapter; default backend vroom-express |
| Trackers and custom fields matched by display name (`"[VRP] Job"`, `"Skills"`) | Explicit configuration; plugin-owned tables for resources |
| Cost matrix had to be provided to the database | Travel times from a routing engine (OSRM) via VROOM |

## 2. Architecture overview

```
+------------------------+          +---------------------------+
| Redmine                |          | srv_vroom (Compose)       |
|  redmine_gtt (geometry)|   HTTP   |  vroom-express            |
|  redmine_issue_datetime| <------> |  VROOM 1.15+              |
|  redmine_gtt_scheduler |   JSON   |  OSRM (regional extract)  |
+------------------------+          +---------------------------+
```

- `redmine_gtt` provides issue geometry.
- `redmine_issue_datetime` provides time windows (start/end timestamps)
  and receives the solved times back.
- `redmine_gtt_scheduler` owns resources, solver runs, and the workflow.
- The solver is a separate service. No PostgreSQL extension is required,
  which keeps the plugin installable on any Redmine (including managed
  databases) and lets VROOM upgrades happen as an image bump.

### Solver adapter

A small interface isolates the backend:

```ruby
class Scheduler::Adapter
  def solve(problem) -> Solution   # problem/solution are plain Ruby objects
end
```

Backends:

- `VroomExpressAdapter` (v1 default): builds the VROOM JSON request,
  POSTs to vroom-express, parses the solution.
- Future candidates behind the same interface: pgvroom (if it matures to
  a released, packaged extension), a revived pg_scheduleserv.

## 3. Data model (plugin-owned tables)

```ruby
# Workers, crews, or vehicles that can be assigned work
create_table :scheduler_resources do |t|
  t.references :project, null: false
  t.string  :name, null: false
  t.references :user                # optional link to a Redmine user
  t.datetime :available_from        # working hours (time of day pattern TBD)
  t.datetime :available_to
  t.st_point :start_location, srid: 4326   # via redmine_gtt / rgeo
  t.st_point :end_location, srid: 4326
  t.integer :capacity               # optional, single dimension in v1
  t.string  :skills, array-ish serialization  # optional
  t.boolean :active, default: true
end

# One optimization run: scope, status, raw request/response, result
create_table :scheduler_runs do |t|
  t.references :project, null: false
  t.references :user, null: false   # who started it
  t.date    :scheduled_on, null: false   # the day being planned (v1: single day)
  t.string  :status, null: false    # draft / solving / proposed / applied / failed / discarded
  t.text    :request_payload        # VROOM request (debugging, reproducibility)
  t.text    :response_payload       # VROOM response
  t.text    :error_message
  t.timestamps
end

# Proposed (and later applied) assignments belonging to a run
create_table :scheduler_assignments do |t|
  t.references :scheduler_run, null: false
  t.references :issue, null: false
  t.references :scheduler_resource, null: false
  t.integer  :sequence, null: false      # order within the route
  t.datetime :starts_at, null: false     # solver output
  t.datetime :ends_at, null: false
  t.integer  :travel_seconds             # from previous stop
end
```

## 4. Mapping Redmine to VROOM

| VROOM concept | Source in Redmine |
| --- | --- |
| `job.location` | Issue geometry from redmine_gtt (point; for lines/polygons: centroid in v1) |
| `job.time_windows` | `issue_datetimes.starts_at/ends_at`; open window when absent |
| `job.service` | `issues.estimated_hours` (converted to seconds; configurable default when empty) |
| `job.priority` | Issue priority position (no name matching) |
| `job.skills` | Optional mapping from a configured custom field (explicit setting: field id, not field name) |
| `vehicle` | `scheduler_resources` row: start/end location, working hours as `time_window`, skills, capacity |
| travel times | Computed by VROOM through OSRM; no matrix handling in the plugin |

Issue selection for a run: a project plus a standard Redmine issue query
(saved query id or ad hoc filters), restricted to issues that have
geometry and are open. Issues without geometry are listed as excluded,
never silently dropped.

v1 models **jobs only**. Shipments (pickup and delivery pairs) and breaks
are explicitly out of scope for v1 and tracked as later phases.

## 5. Workflow: propose, then apply

1. **Compose**: dispatcher opens the Scheduler view in a project, picks
   the day, the issue scope, and the resources to plan with.
2. **Solve**: the run is created (`solving`) and the adapter is called in
   a background job. Request and response payloads are stored on the run.
3. **Review**: the run becomes `proposed`. The UI shows routes on the map
   (redmine_gtt / OpenLayers) and an hour-level timeline per resource
   (rendered by redmine_canvas_gantt from the assignment data). Unassigned
   jobs are listed with the reason VROOM gave.
4. **Apply**: on confirmation, for each assignment the plugin writes
   `starts_at` / `ends_at` through redmine_issue_datetime and sets
   `assigned_to` when the resource is linked to a user. All changes are
   journalized with a note referencing the run. The run becomes `applied`.
5. Runs can also be `discarded` without touching any issue.

Nothing modifies issues before the apply step. A run is reproducible from
its stored request payload.

## 6. UI

- Project menu entry "Scheduler" (module permission based).
- Run list, run detail (map + timeline + assignment table), resource
  administration under project settings.
- Map rendering reuses redmine_gtt's OpenLayers setup; the route geometry
  returned by VROOM (`g` flag via OSRM) is displayed per resource.

## 7. Permissions

- `view_scheduler`: see runs and results.
- `manage_scheduler`: create/solve/apply/discard runs, manage resources.
- Applying additionally requires edit permission on each affected issue;
  issues the user cannot edit block the apply with a clear message.

## 8. Infrastructure: solver service

The solver runs as a separate service next to Redmine, typically a small
Docker Compose stack:

- `vroom-express` with VROOM 1.15+.
- OSRM with a regional extract (for example Geofabrik Japan), `car`
  profile first; profile per resource type is a later phase.
- Internal network only; the plugin reaches it via a configured base URL
  (plugin setting, per instance). No authentication in v1 assuming a
  private network; document the assumption. An example compose file will
  ship in this repository under `contrib/`.

## 9. Dependencies

- Redmine 6.x / RedMica current line
- redmine_gtt (geometry)
- redmine_issue_datetime (time storage; hard dependency)
- redmine_canvas_gantt (timeline rendering; soft dependency, the run
  detail degrades to the table without it)

## 10. Phasing

1. **Phase 1**: data model, VroomExpress adapter, jobs-only solve,
   apply step, plain table UI. No map, no timeline.
2. **Phase 2**: map view of routes, canvas_gantt timeline, unassigned
   job diagnostics.
3. **Phase 3**: skills and capacity, resource working-hour patterns,
   multi-day planning.
4. **Phase 4**: shipments (pickup/delivery), breaks, alternative solver
   backends (pgvroom, pg_scheduleserv).

## 11. Testing

- Adapter tests against recorded VROOM request/response fixtures.
- One integration test path against a real vroom-express container
  (compose file in `test/`), excluded from the default suite.
- Model tests for the apply step (journal entries, permission failures,
  partial apply blocking).

## 12. Credits

The 2022 prototype by Ashish Kumar (GSoC, author of pg_scheduleserv)
established the Redmine-to-VROOM mapping this design builds on. The
prototype remains available in this repository's git history.
