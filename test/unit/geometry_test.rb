require File.expand_path('../test_helper', __dir__)

class GeometryTest < ActiveSupport::TestCase
  Geometry = RedmineGttScheduler::Scheduler::Geometry

  def setup
    # The same factory Redmine/redmine_gtt uses, which is the point: `centroid`
    # is not universally available on it, and that is what broke LineString.
    @factory = RGeo::Geographic.spherical_factory(srid: 4326)
  end

  test 'a point returns its own coordinates' do
    assert_equal [139.7, 35.68], Geometry.point_of(@factory.point(139.7, 35.68))
  end

  test 'a line string returns a point on the line, not nil' do
    line = @factory.line_string([
      @factory.point(139.70, 35.68),
      @factory.point(139.75, 35.70),
      @factory.point(139.80, 35.72)
    ])

    coords = Geometry.point_of(line)

    assert_not_nil coords, 'a LineString must yield a representative point'
    # Must be one of the line's own vertices, so it cannot land off the road.
    assert_includes [[139.70, 35.68], [139.75, 35.70], [139.80, 35.72]],
                    coords.map { |v| v.round(2) }
  end

  test 'a two-point line string still yields a point' do
    line = @factory.line_string([@factory.point(139.70, 35.68), @factory.point(139.75, 35.70)])

    assert_not_nil Geometry.point_of(line)
  end

  test 'a polygon yields a point' do
    ring = @factory.linear_ring([
      @factory.point(139.70, 35.68),
      @factory.point(139.72, 35.68),
      @factory.point(139.72, 35.70),
      @factory.point(139.70, 35.70),
      @factory.point(139.70, 35.68)
    ])

    assert_not_nil Geometry.point_of(@factory.polygon(ring))
  end

  test 'nil geometry yields nil' do
    assert_nil Geometry.point_of(nil)
  end

  test 'an empty geometry collection yields nil rather than raising' do
    assert_nil Geometry.point_of(@factory.collection([]))
  end
end
