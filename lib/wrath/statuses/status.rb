module Wrath
  class Status < GameObject
    include Log
    include Fidgit::Event

    trait :timer

    event :on_applied # [self, creature]
    event :on_removed # [self, creature]
    event :on_having_wounded # Not client-side.

    attr_reader :owner # Object this status is applied to.

    def self.type; name.downcase[/[^:]+$/].to_sym; end
    def type; @type ||= self.class.type; end
    def network_apply?; @network_apply; end
    def network_remove?; @network_remove; end

    # If :duration option is missing, duration is indefinite.
    def initialize(owner, options = {})
      options = {
          image: Image["statuses/#{type}.png"],
          network_apply: true,
          network_remove: true,
      }.merge! options

      raise ArgumentError("Owner must be networked") unless owner.networked?

      @owner = owner
      @network_apply = options[:network_apply]
      @network_remove = options[:network_remove]

      super options

      duration = options[:duration]
      duration_timer(duration) if duration < Float::INFINITY
      
      # Ensure that the stat exists.
      parent.statistics[:status, type] = parent.statistics[:status, type] || 0.0

      publish :on_applied, @owner

      log.debug do
        duration = (duration < Float::INFINITY) ? "for #{duration}ms" : "indefinitely"
        "Applied status #{type.inspect} to #{@owner} #{duration}"
      end
    end
    
    def duration_timer(duration)
      after(duration, name: :duration) { remove } unless parent.client?
    end
    
    # Called if the status effect is already on an object.
    # Duration reset to that of the new duration, unless the remaining duration is greater.
    def reapply(options = {})
      new_duration = options[:duration]
      if new_duration > timer_time_remaining(:duration)
        stop_timer :duration if timer_exists? :duration
        duration_timer(new_duration) if new_duration < Float::INFINITY
      end
    end

    def update
      if @owner and @owner.local? and @owner.controlled_by_player?
        parent.statistics[:status, type] = parent.statistics[:status, type] + (parent.frame_time / 1000.0)
      end
      
      super
    end

    def draw
      # Disable the default draw.
    end

    # Status effect has been removed.
    def remove
      return unless @owner

      old_owner = @owner
      @owner = nil
      old_owner.remove_status(type)
      log.debug { "Removed status #{type.inspect} from #{old_owner}" }
      publish :on_removed, old_owner
    end
  end
end