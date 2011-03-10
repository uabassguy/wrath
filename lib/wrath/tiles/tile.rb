class Tile < GameObject
  WIDTH = HEIGHT = 8
  VERTICAL_SCALE = 0.75

  attr_reader :speed, :contents

  def ground_level; @ground_level; end

  def sprite_position; self.class.const_get(:SPRITE_POSITION); end

  def initialize(options = {})
    options = {
      zorder: ZOrder::TILES,
      factor_y: VERTICAL_SCALE,
      ground_level: 0,
      speed: 1,
    }.merge! options

    @ground_level = options[:ground_level]
    @speed = options[:speed]

    @@sprites ||= SpriteSheet.new("tiles_8x8.png", WIDTH, HEIGHT, 8)

    super

    @type = options[:position]

    @contents = []

    self.image = @@sprites[*sprite_position]
    self.x = (options[:grid][0] + 0.5) * WIDTH
    self.y = (options[:grid][1] + 0.5) * HEIGHT * VERTICAL_SCALE
  end

  def add(object)
    @contents << object unless @contents.include? object
    self
  end

  def remove(object)
    @contents.delete(object)
    object
  end
end