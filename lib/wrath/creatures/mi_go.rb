module Wrath
  class MiGo < Humanoid
    DAMAGE = 15

    def hurts?(other); other.controlled_by_player?; end

    def initialize(options = {})
      options = {
          flying_height: 4,
          walk_interval: 0,
          damage_per_hit: DAMAGE,
          favor: 12,
          health: 20,
          encumbrance: 0.8,
          animation: "mi_go_10x8.png",
      }.merge! options

      super(options)
    end
  end
end