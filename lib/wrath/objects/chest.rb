module Wrath
class Chest < Container
  trait :timer

  PLAYER_TRAPPED_DURATION = 2000

  CLOSED_SPRITE_FRAME = 0
  OPEN_SPRITE_FRAME = 1

  EXPLOSION_H_SPEED = 0.5..1.0
  EXPLOSION_Z_VELOCITY = 0.5..0.9
  EXPLOSION_NUMBER = 15..20

  # Minimum "size" of a creature so it bounces the chest it is in.
  MIN_BOUNCE_ENCUMBRANCE = 0.4

  CHEST_OPEN_SOUND = "objects/chest_close.ogg"
  CHEST_CLOSED_SOUND = "objects/chest_close.ogg"
  CHEST_SACRIFICED_SOUND = "objects/rock_sacrifice.ogg"

  alias_method :open?, :empty?
  alias_method :closed?, :full?

  public
  def initialize(options = {})
    options = {
      favor: -10,
      encumbrance: 0.5,
      elasticity: 0.6,
      z_offset: -2,
      animation: "chest_8x8.png",
      hide_contents: true,
      drop_velocity: [0, 0.15, 0.5],
    }.merge! options

    super options

    @death_explosion = Emitter.new(Splinter, parent, number: EXPLOSION_NUMBER, h_speed: EXPLOSION_H_SPEED,
                                           z_velocity: EXPLOSION_Z_VELOCITY)


    # Ensure our initial state is correct.
    open? ? open : close
  end

  public
  def can_be_activated?(actor)
    (closed? and actor.empty_handed?) or open?
  end

  public
  def activated_by(actor)
    @parent.send_message Message::PerformAction.new(actor, self) if parent.host?

    if closed?
      # Open the chest and spit out its contents.
      drop
    else
      item = actor.contents
      if item
        # Put object into chest.
        actor.drop
        pick_up(item)
      else
        # Pick up the empty chest.
        actor.pick_up(self)
      end
    end
  end

  public
  def on_having_dropped(object)
    super(object)
    open
    Sample[CHEST_CLOSED_SOUND].play
    stop_timer :bounce
    object.position = [x, y, z + 6] # So the object pops out the top of the chest.
  end

  public
  def sacrificed(actor, altar)
    Sample[CHEST_SACRIFICED_SOUND].play
    super(actor, altar)
  end

  def on_having_picked_up(object)
    super(object)
    close

    Sample[CHEST_CLOSED_SOUND].play if parent.started? # Don't make noises before game starts!

    unless parent.client?
      if object.is_a? Creature and object.encumbrance >= MIN_BOUNCE_ENCUMBRANCE
        every(1500 + rand(500), name: :bounce) { self.z_velocity = 0.8 }
      end

      if contents.controlled_by_player?
        after(PLAYER_TRAPPED_DURATION) { drop if contents == object }
      end
    end
  end

  protected
  def open
    self.image = @frames[OPEN_SPRITE_FRAME]
  end

  protected
  def close
    self.image = @frames[CLOSED_SPRITE_FRAME]
  end
end
end