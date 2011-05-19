module Wrath
  class BlueMeanie < Humanoid
    def ground_level; super + ((@state == :thrown) ? 0 : 6); end

    def initialize(options = {})
      options = {
        favor: 8,
        health: 20,
        walk_interval: 0,
        encumbrance: 0.4,
        z_offset: -2,
        animation: "blue_meanie_10x8.png",
      }.merge! options

      super(options)
    end
  end
end