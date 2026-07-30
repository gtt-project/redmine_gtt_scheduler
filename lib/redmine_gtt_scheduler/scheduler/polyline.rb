module RedmineGttScheduler
  module Scheduler
    # Decoder for the encoded polyline VROOM returns for a route when asked for
    # geometry (the `g` option).
    #
    # Precision is 5, established against a live VROOM 1.15 + OSRM stack rather
    # than assumed: decoding the same string at precision 6 divides every
    # coordinate by ten, which silently relocates a route to the Gulf of Guinea
    # instead of failing. That is why plausible? exists and why callers are
    # expected to use it.
    module Polyline
      PRECISION = 5

      # => [[lon, lat], ...]; empty for nil, blank or malformed input.
      def self.decode(encoded, precision: PRECISION)
        encoded = encoded.to_s.strip
        return [] if encoded.empty?

        factor = 10.0**precision
        coordinates = []
        index = 0
        lat = 0
        lng = 0
        length = encoded.length

        while index < length
          lat_delta, index = read_delta(encoded, index, length)
          return [] if lat_delta.nil?

          lng_delta, index = read_delta(encoded, index, length)
          return [] if lng_delta.nil?

          lat += lat_delta
          lng += lng_delta
          coordinates << [lng / factor, lat / factor]
        end
        coordinates
      end

      # Cheap guard against a precision or format change upstream. Coordinates
      # must be inside the valid ranges, and at least one point of the line must
      # fall near at least one of the stops it is supposed to join. Deliberately
      # not "the line starts at the first stop": a route legitimately begins at
      # the resource's own location, which is not one of the stops. A
      # factor-of-ten error fails both conditions.
      def self.plausible?(coordinates, near: [], tolerance_degrees: 1.0)
        return false if coordinates.empty?
        return false unless coordinates.all? { |lon, lat| lon.abs <= 180 && lat.abs <= 90 }
        return true if near.empty?

        coordinates.any? do |lon, lat|
          near.any? do |ref_lon, ref_lat|
            (lon - ref_lon).abs <= tolerance_degrees && (lat - ref_lat).abs <= tolerance_degrees
          end
        end
      end

      # Reads one zigzag-encoded varint. Returns [value, next_index], or
      # [nil, index] when the input ends mid-value.
      def self.read_delta(encoded, index, length)
        shift = 0
        result = 0
        loop do
          return [nil, index] if index >= length

          byte = encoded[index].ord - 63
          index += 1
          # Encoded polyline uses printable ASCII 63..126, so anything outside
          # 0..63 after the offset is not this format. Rejecting it here is what
          # keeps malformed input returning [] instead of arbitrary coordinates.
          return [nil, index] unless byte.between?(0, 63)
          result |= (byte & 0x1f) << shift
          shift += 5
          break if byte < 0x20
        end
        [(result & 1).zero? ? result >> 1 : ~(result >> 1), index]
      end

      private_class_method :read_delta
    end
  end
end
