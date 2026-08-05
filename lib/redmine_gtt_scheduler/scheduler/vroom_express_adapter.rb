require 'json'
require 'net/http'
require 'uri'

module RedmineGttScheduler
  module Scheduler
    # Talks to a vroom-express instance over HTTP JSON.
    # https://github.com/VROOM-Project/vroom-express
    class VroomExpressAdapter < Adapter
      def initialize(url: nil, transport: nil)
        @url = url || RedmineGttScheduler.vroom_url
        @transport = transport
      end

      def solve(problem)
        request = build_request(problem)
        response = parse_json(post(request))
        if response['code'].to_i != 0
          raise SolverError, "VROOM error #{response['code']}: #{response['error']}"
        end

        build_solution(problem, request, response)
      end

      def build_request(problem)
        request = {
          'jobs' => problem.jobs.map do |job|
            {
              'id' => job.id,
              'location' => job.location,
              'service' => job.service,
              'time_windows' => [job.time_window],
              'priority' => job.priority
            }.tap do |j|
              j['skills'] = job.skills if job.skills.present?
              j['delivery'] = job.delivery if job.delivery.present?
            end
          end,
          'vehicles' => problem.vehicles.map do |vehicle|
            {
              'id' => vehicle.id,
              'start' => vehicle.start,
              'end' => vehicle.end,
              'time_window' => vehicle.time_window
            }.tap do |v|
              v['skills'] = vehicle.skills if vehicle.skills.present?
              v['capacity'] = vehicle.capacity if vehicle.capacity.present?
            end
          end
        }
        # `g` asks VROOM for the road geometry of each route. It costs response
        # size and a little solver time, hence the setting.
        request['options'] = {'g' => true} if RedmineGttScheduler.request_geometry?
        request
      end

      private

      def post(request)
        return @transport.call(request.to_json) if @transport

        uri = URI.parse(@url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = 10
        http.read_timeout = RedmineGttScheduler.solver_timeout
        http.post(uri.path.presence || '/', request.to_json,
                  'Content-Type' => 'application/json').body
      rescue SystemCallError, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
        raise SolverError, "solver unreachable at #{@url}: #{e.message}"
      end

      def parse_json(body)
        JSON.parse(body.to_s)
      rescue JSON::ParserError => e
        raise SolverError, "invalid solver response: #{e.message}"
      end

      # Only routes that actually carry geometry; absent when `g` was not asked
      # for, which the map handles by falling back to straight legs.
      def geometries_of(response)
        response.fetch('routes', []).each_with_object({}) do |route, out|
          geometry = route['geometry']
          out[route['vehicle']] = geometry if geometry.present?
        end
      end

      def build_solution(problem, request, response)
        assignments = []
        response.fetch('routes', []).each do |route|
          sequence = 0
          previous_duration = 0
          route.fetch('steps', []).each do |step|
            travel = step['duration'].to_i - previous_duration
            previous_duration = step['duration'].to_i
            next unless step['type'] == 'job'

            sequence += 1
            service_start = step['arrival'].to_i + step['waiting_time'].to_i
            assignments << Solution::Assignment.new(
              issue_id: step['id'],
              # Multi-day problems use synthetic vehicle ids (one vehicle
              # per resource per day); the problem maps them back.
              resource_id: problem.resource_id_for(route['vehicle']),
              sequence: sequence,
              starts_at: Time.at(service_start).utc,
              ends_at: Time.at(service_start + step['service'].to_i).utc,
              travel_seconds: travel
            )
          end
        end

        Solution.new(
          assignments: assignments,
          unassigned_ids: response.fetch('unassigned', []).map { |u| u['id'] },
          request: request,
          raw: response,
          route_geometries: geometries_of(response)
        )
      end
    end
  end
end
