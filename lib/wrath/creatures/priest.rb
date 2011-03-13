# encoding: utf-8

class Priest < Creature
  MAX_HEALTH = 100

  def initialize(options = {})
    options = {
      speed: 2,
      encumbrance: 0.4,
      elasticity: 0.1,
      z_offset: -2,
      health: MAX_HEALTH,
    }.merge! options

    @animation_file = options[:animation]

    super(options)
  end

  def recreate_options
    {
        animation: @animation_file,
        local: remote?, # Invert locality of player created on client.
        number: number
    }.merge! super
  end
end