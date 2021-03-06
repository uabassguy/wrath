module Wrath
# Hot lava is hot.
# If standing in it, you get very burned.
# If standing on it, when it is  filled with rocks, it just sets you on fire.
class Lava < Water
  include Fidgit::Event

  ANIMATION_POSITIONS = [[0, 2], [1, 2]]
  IMAGE_POSITION_FILLED = [2, 3]

  DAMAGE = 20 / 1000.0 # 20/second
  GLOW_COLOR = Color.rgba(255, 100, 0, 20)
  GLOW_SIZE = 0.65

  event :on_having_wounded

  def dangerous?(other); other.flying_height <= 0.01; end

  def edge_type; :hard_curve; end
  def exists?; @exists; end

  def initialize(*args)
    super(*args)

    @body = CP::StaticBody.new
    @body.p = vec2(x, y)
    map.parent.space.add_body @body
    @danger_zone = DangerZone.new(self, @body, :rectangle, (WIDTH / 2), map.parent.space)

    @exists = true
  end

  def destroy
    @danger_zone.destroy
    map.parent.space.remove_body @body

    @exists = false
  end

  def touched_by(object)
    case object
      when Rock
        unless filled?
          object.destroy
          self.filled = true
        end

      when Creature
        unless parent.client?
          object.wound(DAMAGE * parent.frame_time, self, :over_time) unless filled?
          object.apply_status(:burning, duration: Status::Burning::DEFAULT_PRIMARY_BURN_DURATION)
        end

      else
        object.destroy
    end
  end

  def draw
    super

    parent.draw_glow(x, y, GLOW_COLOR, GLOW_SIZE)
  end
end
end