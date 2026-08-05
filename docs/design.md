# redmine_gtt_scheduler v2: Design Document

Status: As built (kept in step with the implementation)
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
  # Takes a Scheduler::Problem, returns a Scheduler::Solution.
  # Both are plain Ruby objects, independent of any backend.
  def solve(problem)
    raise NotImplementedError
  end
end
```

Backends:

- `VroomExpressAdapter` (default): builds the VROOM JSON request,
  POSTs to vroom-express, parses the solution.
- Future candidates behind the same interface: pgvroom (if it matures to
  a released, packaged extension), a revived pg_scheduleserv.

## 3. Data model (plugin-owned tables)

```ruby
# Workers, crews, or vehicles that can be assigned work.
#
# Locations are plain lng/lat floats rather than PostGIS point columns:
# the solver only ever needs a coordinate pair, and plain floats keep the
# table independent of the GIS adapter. Working hours are HH:MM strings
# (validated, compared as minutes since midnight) and apply to every
# working day; working_days is a JSON array of ISO weekdays, empty
# meaning every day. A full per-weekday hour pattern remains future
# work. skills is a JSON array of names from the configured custom
# field's vocabulary; capacity is a single dimension, NULL = unlimited.
create_table :scheduler_resources do |t|
  t.references :project, null: false
  t.references :user                # optional link to a Redmine user
  t.string  :name, null: false
  t.float   :start_lng, null: false
  t.float   :start_lat, null: false
  t.float   :end_lng                # end defaults to start when empty
  t.float   :end_lat
  t.string  :work_starts, null: false, default: '08:00'
  t.string  :work_ends, null: false, default: '17:00'
  t.boolean :active, null: false, default: true
end

# One optimization run: scope, status, raw request/response, result
create_table :scheduler_runs do |t|
  t.references :project, null: false
  t.references :user, null: false   # who started it
  t.date    :scheduled_on, null: false   # first (or only) day being planned
  t.date    :scheduled_until       # last day; NULL = single-day run
  t.string  :status, null: false    # draft / solving / proposed / applied / failed / discarded
  t.text    :request_payload        # VROOM request (debugging, reproducibility)
  t.text    :response_payload       # VROOM response
  t.text    :vehicle_map            # solver vehicle id => [resource id, date]; NULL for single-day
  t.text    :error_message
  t.timestamps
end

# Multi-day runs plan every issue of the range in one optimization, with
# one solver vehicle per resource per working day (synthetic ids; the
# stored vehicle_map translates them back). Single-day runs keep vehicle
# id == resource id, so their payloads read as they always did. The
# range length is capped (14 days) to bound the problem size.

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

# Which resources a run was asked to plan with. A run with no rows plans
# with every active resource (also the behaviour of runs created before
# this table existed).
create_table :scheduler_run_resources do |t|
  t.references :scheduler_run, null: false
  t.references :scheduler_resource, null: false
end
```

The run's `excluded_issues` column stores which issues never became part
of the problem and why (no usable geometry, window outside the planning
day). Route geometry is not stored separately: it is read back out of
the stored solver response when the map needs it.

## 4. Mapping Redmine to VROOM

| VROOM concept | Source in Redmine |
| --- | --- |
| `job.location` | Issue geometry from redmine_gtt, reduced to one point: a Point directly, otherwise the centroid, otherwise a middle vertex (centroid is not available for every type on the geographic factory, notably LineString) |
| `job.time_windows` | `issue_datetimes.starts_at/ends_at`, falling back to the plain dates, clamped to the planning day |
| `job.service` | `issues.estimated_hours` (converted to seconds; configurable default when empty) |
| `job.priority` | Issue priority position, scaled to VROOM's 0..100 (no name matching) |
| `job.skills` | A list-format issue custom field picked in the plugin settings (stored by id, never matched by name); resources carry skill names from the same vocabulary. VROOM skill ids are assigned per request from the sorted union of names in play, so nothing persists ids and renaming values cannot corrupt data |
| `job.delivery` | An integer issue custom field picked in the plugin settings (single load dimension). VROOM requires every job and vehicle to carry the dimension once any does (verified against a live solver), so when active, issues without a value get load 0 and resources without a capacity get the total load, which no route can exceed |
| `vehicle` | `scheduler_resources` row: start/end location, working hours as `time_window` on the planning day, skills, capacity |
| travel times | Computed by VROOM through OSRM; no matrix handling in the plugin |

Issue selection for a run: all open issues of the project that have
geometry, planned with the run's selected resources (all active ones
when no selection was made). Filtering by a saved issue query is a
possible later refinement. Issues without usable geometry or whose
window misses the planning day are listed as excluded with a reason,
never silently dropped.

v1 models **jobs only**. Shipments (pickup and delivery pairs) and breaks
are explicitly out of scope for v1 and tracked as later phases.

## 5. Workflow: propose, then apply

1. **Compose**: dispatcher opens the Scheduler view in a project, picks
   the day (optionally a range of days) and the resources to plan with.
2. **Solve**: the run is created (`solving`) and the adapter is called in
   a background job. Request and response payloads are stored on the run.
   The run always ends in a terminal status: any solver or unexpected
   error marks it `failed` with a message rather than leaving it stuck.
3. **Review**: the run becomes `proposed`. The UI shows each resource's
   route on the map (redmine_gtt / OpenLayers) in its own colour with a
   per-resource toggle, following the real road path when the solver
   returned geometry, and an hour-level timeline per resource (plain
   HTML/CSS rendered by the plugin itself). Unassigned jobs are listed
   with a locally derived reason: VROOM does not report why a job was
   left out, so the plugin re-examines the problem (window outside every
   shift, service longer than any shift, or simply no room) and the UI
   labels the explanations as derived.
4. **Apply**: on confirmation, for each assignment the plugin writes
   `starts_at` / `ends_at` through redmine_issue_datetime and sets
   `assigned_to` when the resource is linked to a user. All changes are
   journalized with a note referencing the run. The run becomes `applied`.
5. Runs can also be `discarded` without touching any issue.

Nothing modifies issues before the apply step. A run is reproducible from
its stored request payload.

## 6. UI

- Project menu entry "Scheduler" (module permission based).
- Run list (paginated), run detail (map + timeline + assignment table),
  resource administration.
- Map rendering reuses redmine_gtt's OpenLayers setup via its published
  `gtt:map:ready` event: the plugin wraps the vector layer's style
  function to colour each route per resource and to build the toggle
  legend, without forking the map. The route geometry returned by VROOM
  (`g` option, encoded polyline at precision 5) is decoded and drawn
  when plausible; otherwise the route falls back to straight legs
  between stops, and the UI says which of the two it is showing.

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

- Redmine 6.0 or later
- redmine_gtt (geometry, map rendering)
- redmine_issue_datetime (time storage; hard dependency)

The timeline is rendered by the plugin itself with plain HTML/CSS, so
there is no further UI dependency.

## 10. Phasing

1. **Phase 1** (done): data model, VroomExpress adapter, jobs-only
   solve, apply step, plain table UI.
2. **Phase 2** (done): map view of routes with per-resource colours and
   toggles, real road geometry, hour-level timeline, unassigned job
   diagnostics, per-run resource selection.
3. **Phase 3** (done, issues #24 to #27): skills, capacity, per-resource
   working days, multi-day planning. Full per-weekday hour patterns
   remain future work.
4. **Phase 4** (issue #5): shipments (pickup/delivery), breaks,
   alternative solver backends (pgvroom, pg_scheduleserv).

## 11. Testing

- Adapter tests with an injected transport stub, asserting both the
  request built from a problem and the solution parsed from a response.
- The polyline decoder is tested against a route captured from a live
  VROOM + OSRM stack, which is what pinned the precision at 5: a
  hand-written fixture would only prove the decoder agrees with itself.
- Model tests for the apply step (journal entries, permission failures,
  the tracker-cannot-store-times warning).
- CI matrix: Redmine 6.1 (Ruby 3.4) and 7.0 (Ruby 3.4 and 4.0) on
  PostGIS, with redmine_gtt and redmine_issue_datetime checked out as
  dependencies, plus a `zeitwerk:check` eager-loading gate.

## 12. Credits

The 2022 prototype by Ashish Kumar (GSoC, author of pg_scheduleserv)
established the Redmine-to-VROOM mapping this design builds on. The
prototype remains available in this repository's git history.
