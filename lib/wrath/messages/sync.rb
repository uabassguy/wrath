module Wrath
class Message
  # Synchronise state for all dynamic objects: position and velocity.
  class Sync < Message
    ACCURACY = 10.0 ** 2.0 # Accurate to 2 decimal places.
    RECORD_SEPARATOR = '#'
    DATA_SEPARATOR = ';'

    @@last_data = [] # Data sent in the last sync packet.

    # An empty sync needn't be sent.
    def empty?; @data.empty?; end

    public
    def initialize(objects)
      data = objects.inject([]) do |data, object|
        # id=42, position=[1.9999999999, 1.12345, 1.9], velocity=[2.9999999999, 2.9999999, 2.0]]
        # # => "42;2;1.123;1.9;3;3;2"
        datum = [object.position, object.velocity].flatten
        datum.map! do |n|
          n = (n * ACCURACY).round / ACCURACY # Reduce decimal places.
          (n == n.to_i) ? n.to_i : n
        end

        data << ([object.id] + datum).join(DATA_SEPARATOR)
      end

      # Remove sync data which is identical to last sync.
      culled_data = data - @@last_data
      @@last_data = data

      @data = culled_data.join(RECORD_SEPARATOR)
    end

    protected
    def action(state)
      @data = @data.split(RECORD_SEPARATOR)

      @data.each do |data|
        data = data.split(DATA_SEPARATOR)
        id, position, velocity = data[0].to_i, data[1..3].map {|n| n.to_f }, data[4..6].map {|n| n.to_f }

        object = object_by_id(id)
        if object
          object.sync(position, velocity)
        else
          log.error { "#{self.class} could not sync object ##{id}" }
        end
      end
    end

    # Optimise dump to produce little data, since this data is sent very often.
    public
    def marshal_dump
      @data
    end

    public
    def marshal_load(data)
      @data = data
    end
  end
end
end