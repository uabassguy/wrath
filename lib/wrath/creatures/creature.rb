module Wrath

  # Any sort of living being.
class Creature < Container
  extend Forwardable

  include Fidgit::Event
  include HasStatus

  event :on_wounded

  trait :timer

  ACTION_DISTANCE = 12

  EXPLOSION_H_SPEED = 0.04..0.5
  EXPLOSION_Z_VELOCITY = 0.1..0.3

  WOUND_FLASH_PERIOD = 200
  AFTER_WOUND_FLASH_DURATION = 100
  HURT_COLOR = Color.rgba(255, 0, 0, 150)

  WALK_ANIMATION_DELAY = 200
  STAND_UP_DELAY = 1000
  FRAME_WALK1 = 0
  FRAME_WALK2 = 1
  FRAME_LIE = 2
  FRAME_THROWN = 2
  FRAME_MOUNTED = 0
  FRAME_CARRIED = 2
  FRAME_SLEEP = 3
  FRAME_DEAD = 3

  THROW_MOVING_SPEED_MULTIPLIER = 3 # Speed things are thrown at, compared to own speed.
  THROW_STATIONARY_SPEED = 1
  THROW_UP_SPEED = 0.5
  MAX_THROW_SPEED = 5.0 # Try to prevent fast objects falling off the screen.

  KNOCK_DOWN_SPEED_V  = 0.75
  KNOCK_DOWN_SPEED_H = 3

  PLAYER_STAND_UP_DELAY = 750 # Don't annoy the player.
  CREATURE_STAND_UP_DELAY = 2000 # Give the player time to grab the creature.

  attr_reader :state, :speed, :health, :player, :max_health, :facing, :strength
  attr_reader :flying_height

  attr_writer :player, :state, :facing, :strength
  alias_method :carrying?, :full?
  alias_method :empty_handed?, :empty?

  def media_folder; 'creatures'; end
  def mount?; false; end
  def alive?; @health > 0; end
  def dead?; @health <= 0; end
  def facing=(angle); @facing = angle % 360; end
  def controlled_by_player?; not @player.nil?; end
  def can_be_picked_up?(container); ((@state == :lying) and (not hurts?(container))) or super; end
  def stand_up_delay; controlled_by_player? ? PLAYER_STAND_UP_DELAY : CREATURE_STAND_UP_DELAY; end
  def can_hit?(other)
    super(other) and [:standing, :walking, :mounted].include? @state
  end

  def ground_level; super + (([:lying, :thrown].include? @state) ? 0 : @flying_height); end

  public
  def initialize(options = {})
    options = {
        flying_height: 0,
        health: 10000,
        strength: 1.0,
        z_offset: -2,
        facing: 0,
        sacrifice_particle: BloodDroplet,
    }.merge! options

    super options

    @flying_height = options[:flying_height]
    @max_health = @health = options[:health]
    @speed = options[:speed]
    @strength = options[:strength]
    @facing = options[:facing]

    @death_explosion = Emitter.new(BloodDroplet, parent, number: ((favor / 5) + 4), h_speed: EXPLOSION_H_SPEED,
                                            z_velocity: EXPLOSION_Z_VELOCITY)

    @state = :standing
    @player = nil

    @first_wounded_at = @last_wounded_at = nil

    @walking_animation = @frames[FRAME_WALK1..FRAME_WALK2]
    @walking_animation.delay = WALK_ANIMATION_DELAY
  end

  public
  def die!
    # Create a corpse to replace this fellow. This will be created simultaneously on all machines, using the next available id.
    corpse = Corpse.create(parent: parent, animation: @frames[FRAME_DEAD..FRAME_DEAD], z_offset: z_offset,
                  encumbrance: encumbrance, position: position, velocity: velocity,
                  emitter: @death_explosion, local: (not parent.client?),
                  factor_x: factor_x, factor_y: factor_y)

    drop unless empty_handed?

    @death_explosion.emit([x, y, z + height / 2], thrown_by: [self, corpse]) if @death_explosion

    parent.lose!(player) if player and not parent.winner

    destroy
  end

  protected
  def draw_self
    super

    if @overlay_color
      image.silhouette.draw_rot(x, y - z, y, 0, center_x, center_y, factor_x, factor_y, @overlay_color)
    end
    
    if health < max_health
      $window.pixel.draw_rot x, y - z - (height + 2), y, 0, 0.5, 0.5, width, 1, Color::BLACK
      $window.pixel.draw_rot x, y - z - (height + 2), y, 0, 0.5, 0.5, width * health / max_health.to_f, 0.5, Color::RED
    end    
  end

  public
  def health=(value)
    original_health = @health
    @health = [[value, 0].max, max_health].min

    if @health < original_health
      @last_wounded_at = milliseconds
      @first_wounded_at = @last_wounded_at unless @first_wounded_at
    end

    # Synchronise health from the server to the client.
    if @health != original_health and parent.host?
      parent.send_message(Message::SetHealth.new(self))
    end

    die! if @health == 0

    if @health < original_health
      publish :on_wounded, original_health - @health
    end

    @health
  end

  public
  def stand_up
    if @state == :lying
      parent.send_message(Message::StandUp.new(self)) if parent.host?
      @state = :standing
    end
  end

  protected
  def effective_speed
    contents ? (@speed * ([strength - contents.encumbrance, 1].min)) : @speed
  end

  public
  def on_having_dropped(object)
    if alive?
      object.x_velocity = x_velocity * THROW_MOVING_SPEED_MULTIPLIER
      # Give a little push if you are stationary, so that it doesn't just land at their feet.
      object.x_velocity += factor_x * THROW_STATIONARY_SPEED if (x_velocity == 0 and y_velocity == 0)

      object.y_velocity = y_velocity * THROW_MOVING_SPEED_MULTIPLIER
      object.z_velocity = z_velocity + THROW_UP_SPEED

      # Cap the thrown speed.
      h_speed = Math::sqrt(object.x_velocity ** 2 + object.y_velocity ** 2)
      if h_speed > MAX_THROW_SPEED
        object.x_velocity *= MAX_THROW_SPEED / h_speed
        object.y_velocity *= MAX_THROW_SPEED / h_speed
      end
    end

    nil
  end

  public
  def local=(value)
    # Player avatar never change locality.
    super(value) unless controlled_by_player?
  end

  public
  def mount(mount)
    mount.pick_up(self)
  end

  public
  # The creature's ghost has ascended, after sacrifice.
  def ghost_disappeared

  end

  public
  # The creature tries to perform an action, at the will of a Player.
  def action
    # Find all objects within range, then check them in order
    # and activate the first on we can (generally, pick it up).
    near_objects = parent.objects - [self]
    near_objects.select! {|g| distance_to(g) <= ACTION_DISTANCE }
    near_objects.sort_by! {|g| distance_to(g) }

    target = near_objects.find {|o| o.can_be_activated?(self) }

    # Special case if we are carrying something that we can't drop.
    if not target and not empty_handed? and not @contents.can_be_dropped?
      return
    end

    if parent.client?
      # Client needs to ask permission first.
      parent.send_message(Message::RequestAction.new(self, target))
      # Host/local can do it immediately.
    else
      perform_action(target)
    end
  end

  public
  def update
    super

    # Ensure that state is updated remotely.
    case @state
      when :standing
        @state = :walking if [x_velocity, y_velocity] != [0, 0]
      when :walking
        @state = :standing if velocity == [0, 0, 0]

        # Turn if we are walking into a wall. 500 degrees/second.
        @facing += 0.5 * parent.frame_time if position == @last_position
        @last_position = position
    end

    update_color

    # Ensure any carried object faces in the same direction as the player.
    if carrying?
      if (factor_x > 0 and contents.factor_x < 0) or
          (factor_x < 0 and contents.factor_x > 0)
        contents.factor_x *= -1
      end
    end

    self.image = case state
                   when :walking
                     z <= ground_level ? @walking_animation.next : @frames[FRAME_WALK1]
                   when :standing
                     @frames[FRAME_WALK1]
                   when :carried
                     @frames[FRAME_CARRIED]
                   when :mounted
                     @frames[FRAME_MOUNTED]
                   when :lying
                     @frames[FRAME_LIE]
                   when :thrown
                     @frames[FRAME_THROWN]
                   when :sleeping
                     @frames[FRAME_SLEEP]
                   else
                     raise "unknown state: #{state}"
                 end
  end

  protected
  def on_being_picked_up(container)
    super(container)
    @state = (container.is_a?(Creature) and container.mount?) ? :mounted : :carried
    drop
    stop_timer :stand_up
  end

  protected
  def on_being_dropped(container)
    super(container)
    @state = :thrown
  end

  protected
  def reset_color
    @overlay_color = nil
  end

  public
  def move(angle)
    angle += status(:poisoned).displacement_angle if poisoned?
    set_body_velocity(angle, effective_speed)
  end

  public
  def on_collision(other)
    collided = super(other)

    # Make being hit with something heavy knock you over.
    if not collided and
        state != :thrown and
        other.can_knock_down_creature?(self) and
        other.thrown_by.any? {|o| o.is_a? Creature } # So items popping out of chests don't knock you down.

      knocked_down_by(other)
    end

    collided
  end

  public
  def wound(damage, wounder, type)
    raise ArgumentError.new("bad type: #{type.inspect}") unless [:hit, :over_time].include? type

    if local? and controlled_by_player?
      stats = parent.statistics
      wounder_name = wounder.class.name[/[^:+]+$/].to_sym

      stats[:damage, :total] = (stats[:damage, :total] || 0) + damage
      stats[:damage, :type, wounder_name] = (stats[:damage, :type, wounder_name] || 0) + damage

      if damage >= health
        stats.increment(:deaths, :total)
        stats.increment(:deaths, :type, wounder_name)
      end
    end

    self.health -= damage

    if alive? and type == :hit
      knocked_down_by(wounder)
    end

    self
  end

  public
  # You were knocked down by someone else.
  def knocked_down_by(knocker)
    parent.send_message(Message::KnockedDown.new(self, knocker)) if parent and parent.host?

    @state = :thrown
    @thrown_by += [knocker] + knocker.thrown_by
    @thrown_by << knocker.container if knocker.container and knocker.container.mount?
    drop unless empty_handed?

    angle = Gosu::angle(knocker.x, knocker.y, x, y)
    self.velocity = [offset_x(angle, KNOCK_DOWN_SPEED_H), offset_y(angle, KNOCK_DOWN_SPEED_H), KNOCK_DOWN_SPEED_V]

    knocker.knocked_someone_down(self)

    nil
  end

  protected
  def update_color
    # Reset colour if it was a while since we were wounded.
    if @first_wounded_at
      if milliseconds - @last_wounded_at > AFTER_WOUND_FLASH_DURATION
        reset_color
        @first_wounded_at = @last_wounded_at = nil
      else
        if (milliseconds - @first_wounded_at).div(WOUND_FLASH_PERIOD) % 2 == 0
          @overlay_color = HURT_COLOR
        else
          reset_color
        end
      end
    end
  end

  protected
  def on_stopped
    case @state
      when :thrown
        # Stand up if we were thrown.
        @state = :lying
        after(stand_up_delay, name: :stand_up) { stand_up } unless parent.client?
    end

    super
  end
end
end