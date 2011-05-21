module Wrath
  class Lobby < Gui

    READY_COLOR = Color.rgb(0, 0, 0)
    UNREADY_BACKGROUND_COLOR = Color.rgb(50, 50, 50)
    READY_BACKGROUND_COLOR = Color.rgb(0, 255, 0)
    DISAMBIGUATION_SUFFIX = '_'

    FREE_PRIESTS = [:monk, :prophet, :thaumaturge, :witch] # Priests that are unlocked automatically.
    FREE_LEVELS = [Level::Forest] # Levels that are unlocked automatically.

    public
    def accept_message?(message); [Message::NewGame, Message::UpdateLobby].find {|m| message.is_a? m }; end

    public
    def initialize(network, opponent_name, self_name = nil)
      super()

      self_name = settings[:player, :name] unless self_name

      @network = network

      @player_names = [self_name, opponent_name]
      @player_names.reverse! if @network.is_a? Client
      @player_names[1] += DISAMBIGUATION_SUFFIX if @player_names[1] == @player_names[0]

      @player_number = host? ? 0 : 1

      # Work out which priests can be played.
      @unlocked_priests = FREE_PRIESTS.dup
      (Priest::NAMES - FREE_PRIESTS).each do |priest|
        @unlocked_priests << priest if achievement_manager.unlocked?(:priest, priest)
        @unlocked_priests.sort!
      end

      on_input(:escape) { game_state_manager.pop_until_game_state Menu }

      heading = case @network
        when Server
          "Host"

        when Client
          @network.send_msg(Message::ClientReady.new(settings[:player, :name]))
          "Client"

        else
          "Lobby"
      end

      pack :vertical, spacing: 0 do
        label heading, font_size: 32

        player_grid

        level_picker
      end

      pack :horizontal do
        button "Cancel" do
          game_state_manager.pop_until_game_state Menu
        end

        if @network
          @ready_button = toggle_button("Ready") do |sender, value|
            update_ready @player_number, value
            send_message(Message::UpdateLobby.new(:ready, @player_number, value))
          end
        end

        if client?
          label "Wait for host to start a game"
        else
          @start_button = button("Start", enabled: local?) do
            new_game @level_picker.value
          end
        end
      end
    end

    def host?; @network.is_a? Server; end
    def client?; @network.is_a? Client; end
    def local?; @network.nil?; end

    def send_message(message)
      if client?
        @network.send_msg(message)
      else
        @network.broadcast_msg(message)
      end
    end

    protected
    def level_picker
      label "Level"

      pack :horizontal, spacing: 0 do
        @level_picker = combo_box value: Level.levels[0], width: $window.width * 0.75, enabled: (not client?) do
          subscribe :changed do |sender, level|
            send_message(Message::UpdateLobby.new(:level, level)) if host?
          end
        end

        label "", icon: ScaledImage.new(Image["combo_arrow.png"], 1.5), padding: 0
      end
    end

    public
    def setup
      super
      # Ensure that any unlocks are updated.
      update_level_picker
      enable_priest_options
    end

    protected
    def update_level_picker
      # Work out which levels can be played.
      if client?
        # Can't modify the levels; the host decides that.
        unlocked_levels = Levels.levels
      else
        unlocked_levels = FREE_LEVELS.dup
        (Level.levels - FREE_LEVELS).each do |level|
          unlocked_levels << level if achievement_manager.unlocked?(:level, level.name[/[^:]+$/].to_sym)
        end
      end

      old_value = @level_picker.value # Preserve the previous setting.
      @level_picker.clear
      unlocked_levels.each do |level|
        @level_picker.item(level.to_s, level, icon: ScaledImage.new(level.icon, $window.sprite_scale))
      end
      @level_picker.value = old_value if old_value
    end

    protected
    def player_grid
      @ready_indicators = []
      @num_readies = 0

      label "Players"
      pack :grid, num_columns: 3, spacing_v: 4 do
        @player_names.each_with_index do |player_name, player_number|
          player_row player_name, player_number
        end
      end
    end

    protected
    def player_row(player_name, player_number)
      @player_sprite_combos ||= {}

      is_local = ((player_number == @player_number) or local?)
      pack :horizontal, spacing: 0, padding: 0 do
        @player_sprite_combos[player_name] = combo_box width: 290, enabled: is_local do
          Priest::NAMES.each do |name|
            item Priest.title(name), name, icon: ScaledImage.new(Priest.icon(name), $window.sprite_scale)
          end

          subscribe :changed do |sender, name|
            enable_priest_options

            send_message(Message::UpdateLobby.new(:player, player_number, name)) unless local?
          end
        end
        label "", icon: ScaledImage.new(Image["combo_arrow.png"], 1.5), padding: 0
      end

      @player_sprite_combos[player_name].value = @unlocked_priests[player_number]

      label player_name

      if @network
        @ready_indicators << label('Ready', color: READY_COLOR, background_color: UNREADY_BACKGROUND_COLOR)
      else
        label ''
      end
    end

    public
    # Start a new game. Also called from Message::NewGame.
    def new_game(level)
      if @network
        # Turn off the ready indicators, in case we come back to this state.
        2.times {|i| update_ready(i, false) }
        @ready_button.value = false
      end

      priest_names = @player_sprite_combos.values.map do |combo|
        combo.value
      end

      push_game_state level.new(@network, @player_names, priest_names)
    end

    public
    def update
      @network.update if @network
      super
      @network.flush if @network
    end

    protected
    # Enables and disables all the possible priest sprites, based on what is available.
    def enable_priest_options
      # TODO: Bit of a fudge to prevent this breaking because there aren't two combos.
      return unless @player_sprite_combos.size == 2

      @player_sprite_combos.each_value do |this_combo|
        other_combo = (@player_sprite_combos.values - [this_combo]).first
        this_combo.each do |item|
          item.enabled = ((item.value != other_combo.value) and @unlocked_priests.include? item.value)
        end
      end
    end

    public
    def update_player(player_number, priest_name)
      @player_sprite_combos.values[player_number].value = priest_name
      enable_priest_options
    end

    public
    def update_level(level)
      @level_picker.value = level
    end

    public
    def update_ready(player_number, value)
      if value
        @num_readies += 1
      else
        @num_readies -= 1
      end

      if host?
        @start_button.enabled = (@num_readies == 2)
      end

      @ready_indicators[player_number].background_color = value ? READY_BACKGROUND_COLOR : UNREADY_BACKGROUND_COLOR
    end
  end
end