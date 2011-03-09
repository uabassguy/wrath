class Mushroom < StaticObject
  def initialize(options = {})
    options = {
      factor: 0.7,
      animation: "mushroom_6x5.png",
      collision_type: :scenery,
    }.merge! options

    super options
  end
end