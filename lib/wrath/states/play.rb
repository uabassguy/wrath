module Wrath
class Play < GameState
  extend Forwardable
  trait :timer

  SYNCS_PER_SECOND = 10.0 # Desired speed for sync updates.
  SYNC_DELAY = 1.0 / SYNCS_PER_SECOND
  IDEAL_PHYSICS_STEP = 1.0 / 120.0 # Physics frame-rate.
  DARKNESS_COLOR = Color.rgba(0, 0, 0, 120)
  GLOW_WIDTH = 64

  # Messages accepted after the game has started.
  GAME_STARTED_MESSAGES = [
      Message::Create, Message::Destroy,
      Message::Disaster, Message::EndGame,
      Message::PerformAction, Message::RequestAction, Message::Sync,
      Message::SetFavor, Message::SetHealth
  ]

  # Messages accepted during the setup phase.
  GAME_SETUP_MESSAGES = [
      Message::Create, Message::EndGame, Message::Map,
      Message::StartGame
  ]

  PRIEST_NAMES = %w[druidess priestess shaman witch]
  PRIEST_SPRITES = {}
  PRIEST_NAMES.each do |name|
    PRIEST_SPRITES[name] = "#{name}_8x8.png"
  end

  # Margin in which nothing should spawn.
  module Margin
    TOP = 20
    BOTTOM = 0
    LEFT = 0
    RIGHT = 0
  end

  def_delegators :@map, :tile_at_coordinate

  attr_reader :objects, :map, :players, :network, :space, :altar, :winner

  def networked?; not @network.nil?; end
  def host?; @network.is_a? Server; end
  def client?; @network.is_a? Client; end
  def local?; @network.nil?; end
  def started?; @started; end
  def disaster_interval; 30000 - 1000 * @num_disasters; end
  def level_duration; 300 * 1000; end

  # network: Server, Client, nil
  def initialize(network = nil, player_names, priest_files)
    BaseObject.reset_object_ids

    @@glow = make_glow

    @network, @player_names, @priest_files = network, player_names, priest_files

    super()

    on_input(:escape) do
      send_message(Message::EndGame.new) if networked?
      game_state_manager.pop_until_game_state Lobby
    end

    send_message(Message::NewGame.new(self.class)) if host?

    @last_sync = milliseconds

    init_physics

    @winner = nil
    @objects = []
    @players = []
    @started = false

    @font = Font["pixelated.ttf", 32]

    create_players

    unless client?
      tiles = random_tiles
      create_map(tiles)
      send_message(Message::Map.new(tiles)) if host?

      create_objects

      start_game
    end

    send_message(Message::StartGame.new) if host?
  end

  def self.levels
    unless defined? @@levels
      @@levels = []

      Wrath::constants.each do |const_name|
        const = Wrath.const_get const_name
        if const != Play and const.ancestors.include? Play
          @@levels << const
        end
      end

      @@levels.sort_by! {|level| level.to_s }
    end

    @@levels
  end

  def accept_message?(message)
    accepted_messages = started? ? GAME_STARTED_MESSAGES : GAME_SETUP_MESSAGES

    accepted_messages.find {|m| message.is_a? m }
  end

  def create_map(tiles)
    @map = Map.create(tiles)
  end

  # Start the game, after sending all the init data.
  def start_game
    @time_left = level_duration
    @started = true
    @num_disasters = 0
    @disaster_duration = 0
    after(disaster_interval, name: :disaster) { disaster } unless client?
  end

  def disaster
    @num_disasters += 1
    @disaster_duration = disaster_duration

    unless client?
      send_message Message::Disaster.new if host?
      after(disaster_interval, name: :disaster) { disaster }
    end

    on_disaster
  end

  def send_message(message)
    if client?
      @network.send_msg(message)
    else
      @network.broadcast_msg(message)
    end
  end

  def create_players
    log.info "Creating players"

    @players << Player.create(0, (not client?))
    @players << Player.create(1, (not host?))
  end

  def init_physics
    log.info "Initiating physics"

    @space = CP::Space.new
    @space.damping = 0

    # Wall around the play-field.
    y_margin = 16
    [
      [0, 0, 0, $window.retro_height, :left],
      [0, $window.retro_height, $window.retro_width, $window.retro_height, :bottom],
      [$window.retro_width, $window.retro_height, $window.retro_width, 0, :right],
      [$window.retro_width, y_margin, 0, y_margin, :top]
    ].each do |x1, y1, x2, y2, side|
      Wall.create(x1, y1, x2, y2, side)
    end

    # :static - An immobile object that blocks all movement.
    # :wall - Edge of the screen.
    # :object - players, mobs and carriable objects.
    # :scenery - Doesn't collide with anything at all.

    @space.on_collision(:static, [:static, :wall]) { false }
    @space.on_collision(:scenery, [:particle, :static, :object, :wall, :scenery]) { false }
    @space.on_collision(:particle, :particle) { false }
    @space.on_collision(:particle, :wall) do |particle, wall|
      true
    end

    @space.on_collision(:particle, [:static, :object]) do |a, b|
      if (a.z > b.z + b.height) or (b.z > a.z + a.height)
        false
      else
        a.on_collision(b)
      end
    end

    # Objects collide with static objects, unless they are being carried or heights are different.
    @space.on_collision(:object, :static) do |a, b|
      not ((a.can_pick_up? and a.inside_container?) or (a.z > b.z + b.height) or (b.z > a.z + a.height))
    end

    # Objects collide with the wall, unless they are being carried.
    @space.on_collision(:object, :wall) do |object, wall|
      object.on_collision(wall)
    end

    @space.on_collision(:object, :object) do |a, b|
      # Objects only affect one another on the host/local machine and only if they touch vertically.
      if client?
        false
      elsif not ((a.z > b.z + b.height) or (b.z > a.z + a.height))
        collides = a.on_collision(b)
        collides ||= b.on_collision(a)

        collides
      end
    end
  end

  def create_altar
    # The altar is all-important!
    Altar.create(x: $window.retro_width / 2, y: ($window.retro_height + Margin::TOP) / 2)
  end

  def create_objects(player_spawns)
    log.info "Creating objects"

    @altar = create_altar
    @objects << @altar # Needs to be added manually, since it is a static object.

    # Player 1.
    player1 = Priest.create(local: true, x: altar.x + player_spawns[0][0], y: altar.y + player_spawns[0][1],
                            animation: @priest_files[0])
    players[0].avatar = player1

    # Player 2.
    player2 = Priest.create(local: @network.nil?, x: altar.x + player_spawns[1][0], y: altar.y + player_spawns[1][1],
                            factor_x: -1, animation: @priest_files[1])
    players[1].avatar = player2
  end

  def random_tiles(default_tile)
    # Fill the grid with grass to start with.
    num_columns, num_rows = ($window.retro_width / Tile::WIDTH).ceil, ($window.retro_height / Tile::HEIGHT).ceil
    grid = Array.new(num_rows) { Array.new(num_columns, default_tile) }

    [num_columns, num_rows, grid]
  end

  def setup
    super
    log.info "Started playing"
  end

  def finalize
    log.info "Stopped playing"
  end

  def update
    # Read any incoming messages which will alter our start state.
    @network.update if @network

    if started?
      @time_left -= frame_time
      @disaster_duration -= frame_time

      super

      objects.each {|o| o.update_forces }

      # Ensure that we have one or more physics steps that run at around the same interval.
      total_time = frame_time / 1000.0
      num_steps = total_time.div IDEAL_PHYSICS_STEP
      step = total_time / num_steps
      num_steps.times do
        @space.step step
      end

      # Move carried objects to appropriate positions to prevent desync in movement.
      @objects.each do |object|
        if object.is_a? Container and object.full?
          object.update_contents_position
        end
      end
    end

    # Ensure that any network objects are synced over the network.
    if @network
      sync if started?
      @network.flush
    end
  end

  def draw
    if started?
      # Write the timer out.
      m, s = (@time_left / 1000.0).divmod 60
      @font.draw_rel("%d:%02d" % [m, s], $window.retro_width / 2, 0, ZOrder::GUI, 0.5, 0, 0.25, 0.25, Player::STATUS_COLOR)
      super
    else
      @font.draw_rel("Loading...", 0, 0, ZOrder::GUI, 0, 0, 0.25, 0.25)
    end
  end

  # A player has declared themselves the loser, so the other player wins.
  def lose!(loser)
    win!(loser.opponent)
  end

  # A player has declared themselves the winner.
  def win!(winner)
    @winner = winner
    @winner.win!
    @winner.opponent.lose!
    push_game_state GameOver.new(winner)
  end

  def make_glow
    @@glow = TexPlay.create_image($window, GLOW_WIDTH, GLOW_WIDTH)

    center = @@glow.width / 2.0
    radius =  @@glow.width / 2.0

    @@glow.circle center, center, radius, :filled => true,
      :color_control => lambda {|source, dest, x, y|
        # Glow starts at the edge of the pixel (well, its radius, since glow is circular, not rectangular)
        distance = distance(center, center, x, y)
        dest[3] = (1 - (distance / radius)) ** 2
        dest
      }
  end

  def draw_glow(x, y, color, scale)
    @@glow.draw_rot(x, y, ZOrder::BACK_GLOW, 0, 0.5, 0.5, scale, scale, color, :additive)
  end

  def sync
    if (milliseconds - @last_sync) > SYNC_DELAY
      needs_sync = objects.select {|o| o.network_sync? }
      length = send_message(Message::Sync.new(needs_sync))

      log.debug { "Synchronised #{needs_sync.size} objects in #{length} bytes" }

      @last_sync = milliseconds
    end
  end
end
end