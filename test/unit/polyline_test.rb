require File.expand_path('../test_helper', __dir__)

class PolylineTest < ActiveSupport::TestCase
  Polyline = RedmineGttScheduler::Scheduler::Polyline

  # Captured from a live VROOM 1.15 + OSRM stack (Kansai extract) for a route
  # from [135.3550, 34.7450] via [135.3555, 34.7452] to [135.3560, 34.7455].
  # A hand-written string would not prove the precision is right; this does.
  REAL_ROUTE = 'gcasE}ocyXR?AQ?O?N@PfBCZA@YBgG?e@_@B}@Di@J[FMBM?KG'.freeze
  ROUTE_START = [135.35503, 34.745].freeze

  test 'a real solver polyline decodes to coordinates on the route' do
    coords = Polyline.decode(REAL_ROUTE)

    assert_operator coords.size, :>, 1
    assert_in_delta ROUTE_START[0], coords.first[0], 0.0001
    assert_in_delta ROUTE_START[1], coords.first[1], 0.0001
    # Every point stays in the Nishinomiya neighbourhood the route covers.
    assert(coords.all? { |lon, lat| lon.between?(135.3, 135.4) && lat.between?(34.7, 34.8) })
  end

  # This is the failure the precision guard exists for: decoding at 6 divides
  # every coordinate by ten, putting a Japanese route in the Gulf of Guinea
  # without raising anything.
  test 'decoding at the wrong precision produces implausible coordinates' do
    wrong = Polyline.decode(REAL_ROUTE, precision: 6)

    assert_operator wrong.size, :>, 1
    assert_in_delta 13.5355, wrong.first[0], 0.001
    assert_not Polyline.plausible?(wrong, near: [ROUTE_START])
    assert Polyline.plausible?(Polyline.decode(REAL_ROUTE), near: [ROUTE_START])
  end

  test 'the documented precision is 5' do
    assert_equal 5, Polyline::PRECISION
  end

  test 'blank and nil input decode to nothing rather than raising' do
    assert_empty Polyline.decode(nil)
    assert_empty Polyline.decode('')
  end

  test 'a string truncated mid-value decodes to nothing rather than a bad point' do
    # Cutting the fixture inside a varint leaves an incomplete latitude.
    assert_empty Polyline.decode(REAL_ROUTE[0, 1])
  end

  test 'a known simple polyline decodes to its documented coordinates' do
    # The example from Google's own encoded polyline documentation, as a check
    # that the algorithm itself is right and not just self-consistent.
    coords = Polyline.decode('_p~iF~ps|U_ulLnnqC_mqNvxq`@')

    assert_equal [[-120.2, 38.5], [-120.95, 40.7], [-126.453, 43.252]],
                 coords.map { |lon, lat| [lon.round(3), lat.round(3)] }
  end

  test 'plausibility rejects coordinates outside the valid ranges' do
    assert_not Polyline.plausible?([[200.0, 10.0]])
    assert_not Polyline.plausible?([[10.0, 100.0]])
    assert_not Polyline.plausible?([])
  end

  test 'plausibility passes when no reference points are given' do
    assert Polyline.plausible?([[135.35, 34.74]], near: [])
  end

  test 'plausibility rejects a line nowhere near its stops' do
    assert_not Polyline.plausible?([[2.35, 48.85]], near: [[135.35, 34.74]])
  end

  test 'whitespace-only input decodes to nothing' do
    assert_empty Polyline.decode('   ')
    assert_empty Polyline.decode("\n")
  end

  # Bytes below the encoded-polyline alphabet would otherwise shift into
  # arbitrary coordinates rather than being rejected.
  test 'characters outside the encoded alphabet are rejected' do
    assert_empty Polyline.decode("\x01\x02\x03")
    assert_empty Polyline.decode('abc' + 0.chr + 'def')
  end
end
