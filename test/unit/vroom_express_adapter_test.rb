require File.expand_path('../test_helper', __dir__)

class VroomExpressAdapterTest < ActiveSupport::TestCase
  include SchedulerTestHelper

  Problem = RedmineGttScheduler::Scheduler::Problem
  Adapter = RedmineGttScheduler::Scheduler::VroomExpressAdapter

  def simple_problem
    Problem.new(
      jobs: [
        Problem::Job.new(id: 11, location: [139.7, 35.68], service: 1800,
                         time_window: [1000, 9000], priority: 40)
      ],
      vehicles: [
        Problem::Vehicle.new(id: 21, start: [139.7, 35.68], end: [139.7, 35.68],
                             time_window: [0, 10_000])
      ]
    )
  end

  test 'builds a VROOM request from the problem' do
    transport, requests = stub_transport('code' => 0, 'routes' => [], 'unassigned' => [])
    Adapter.new(transport: transport).solve(simple_problem)

    request = requests.first
    assert_equal [11], request['jobs'].map { |j| j['id'] }
    assert_equal [[1000, 9000]], request['jobs'].first['time_windows']
    assert_equal 1800, request['jobs'].first['service']
    assert_equal [21], request['vehicles'].map { |v| v['id'] }
    assert_equal [0, 10_000], request['vehicles'].first['time_window']
  end

  test 'maps routes to assignments with service start and travel time' do
    response = {
      'code' => 0,
      'routes' => [
        {
          'vehicle' => 21,
          'steps' => [
            {'type' => 'start', 'duration' => 0, 'arrival' => 1000},
            {'type' => 'job', 'id' => 11, 'duration' => 600, 'arrival' => 1600,
             'waiting_time' => 100, 'service' => 1800},
            {'type' => 'end', 'duration' => 2000, 'arrival' => 5000}
          ]
        }
      ],
      'unassigned' => [{'id' => 12}]
    }
    transport, = stub_transport(response)
    solution = Adapter.new(transport: transport).solve(simple_problem)

    assert_equal 1, solution.assignments.size
    assignment = solution.assignments.first
    assert_equal 11, assignment.issue_id
    assert_equal 21, assignment.resource_id
    assert_equal 1, assignment.sequence
    # arrival 1600 + waiting 100 = service starts at 1700, ends 1800s later
    assert_equal Time.at(1700).utc, assignment.starts_at
    assert_equal Time.at(3500).utc, assignment.ends_at
    assert_equal 600, assignment.travel_seconds
    assert_equal [12], solution.unassigned_ids
  end

  test 'raises a solver error for a non-zero VROOM code' do
    transport, = stub_transport('code' => 3, 'error' => 'invalid profile')
    error = assert_raises(RedmineGttScheduler::Scheduler::Adapter::SolverError) do
      Adapter.new(transport: transport).solve(simple_problem)
    end
    assert_includes error.message, 'invalid profile'
  end

  test 'raises a solver error for an unparsable response' do
    transport = ->(_body) { 'not json' }
    assert_raises(RedmineGttScheduler::Scheduler::Adapter::SolverError) do
      Adapter.new(transport: transport).solve(simple_problem)
    end
  end
end
