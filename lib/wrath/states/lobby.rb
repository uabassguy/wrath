module Wrath
  class Lobby < Gui
    READY_COLOR = Color.rgb(0, 0, 0)
    UNREADY_BACKGROUND_COLOR = Color.rgb(50, 50, 50)
    READY_BACKGROUND_COLOR = Color.rgb(0, 255, 0)
    DISAMBIGUATION_SUFFIX = '_'
    CHAT_FONT_HEIGHT = 4
    MAX_CHAT_LINES = 100

    attr_reader :player_names, :network

    public
    def accept_message?(message); [Message::NewGame, Message::UpdateLobby, Message::Say].find {|m| message.is_a? m }; end
    def networked?; !!@network; end
    def host?; @network.is_a? Server; end
    def client?; @network.is_a? Client; end
    def offline?; @network.nil?; end

    public
    def initialize(network, opponent_name, self_name = nil)
      super()

      self_name = settings[:player, :name] unless self_name

      @network = network

      @player_names = [self_name, opponent_name]
      @player_names.reverse! if @network.is_a? Client
      @player_names[1] += DISAMBIGUATION_SUFFIX if @player_names[1] == @player_names[0]

      @player_number = host? ? 0 : 1

      on_input([:enter, :return], :chat_entered) if networked?
    end

    def title
      case @network
        when Server
          t.title.host

        when Client
          @network.send_msg(Message::ClientReady.new(settings[:player, :name]))
          t.title.client

        else
          t.title.offline
      end
    end

    def back_button_pressed
      pop_until_game_state Play
    end

    def chat_entered
      @chat_entry.publish :focus unless @chat_entry.focused?

      return if @chat_entry.text.empty?

      send_message(Message::Say.new((host? ? 0 : 1), @chat_entry.text))
      say(player_names[host? ? 0 : 1], @chat_entry.text)
      @chat_entry.text = ''
    end

    def say(player, message)
      text = @chat_body.text
      text.sub!(/.+\n/, '') if text.count("\n") >= MAX_CHAT_LINES
      text += "\n" unless text.empty?
      text += "#{player}: #{message}"
      @chat_body.text = text
      @chat_window.offset_y = Float::INFINITY # Scroll the window down to the end, so we can see the new text.
    end

    def setup
      super

     # Work out which priests can be played.
      @unlocked_priests = Priest::FREE_UNLOCKS.dup
      (Priest::NAMES - Priest::FREE_UNLOCKS).each do |priest|
        @unlocked_priests << priest if achievement_manager.unlocked?(:priest, priest)
      end
      @unlocked_priests.sort!

      # Ensure that any unlocks are updated.
      update_level_picker
      2.times {|i| update_priests(i) }
      enable_priest_options
    end

    def body
      player_grid

      level_picker

      chat_area if networked?
    end

    def chat_area
      vertical spacing: 0, border_thickness: 0.5, border_color: Color::WHITE, background_color: BACKGROUND_COLOR, padding: 0 do
        @chat_window = scroll_window border_thickness: 0, width: $window.width - 10, height: 28, padding: 1 do
          @chat_body = text_area enabled: false, font_height: CHAT_FONT_HEIGHT, padding: 0, line_spacing: 0.5,
                                 width: $window.width - 20, background_color: BACKGROUND_COLOR
        end

        horizontal padding: 1 do
          @chat_entry = text_area font_height: CHAT_FONT_HEIGHT, align_v: :center, padding: 1, width: $window.width - 75,
                                  border_thickness: 0.25, border_color: Color::WHITE
          button "Send", font_height: CHAT_FONT_HEIGHT, padding: 1.5 do
            chat_entered
          end
        end
      end
    end

    def extra_buttons
      if networked?
        @ready_button = toggle_button(t.button.ready.text, shortcut: :auto) do |sender, value|
          update_ready @player_number, value
          send_message(Message::UpdateLobby.new(:ready, @player_number, value))
        end
      end

      if client?
        label t.label.wait_for_start
      else
        @start_button = button(t.button.start.text, enabled: offline?, shortcut: :auto) do
          new_game(@level_picker.value, @god_picker.value)
        end
      end
    end

    def send_message(message)
      if client?
        network.send_msg(message)
      else
        network.broadcast_msg(message)
      end
    end

    protected
    def level_picker
      grid num_columns: 2, padding: 0, spacing_v: 1, spacing_h: 3 do
        label t.label.map, align_v: :center
        @level_picker = combo_box value: Level::LEVELS.first, enabled: (not client?) do
          subscribe :changed do |sender, level|
            send_message(Message::UpdateLobby.new(:level, level)) if host?
            @god_picker.value = level::GOD
          end
        end

        label t.label.god, align_v: :center
        @god_picker = combo_box value: @level_picker.value::GOD do
          subscribe :changed do |sender, god|
            send_message(Message::UpdateLobby.new(:god, god)) if host?
          end
        end
      end
    end

    def update_priests(combo_index)
      combo = @player_sprite_combos.values[combo_index]
      old_value = combo.value
      combo.clear
      Priest::NAMES.each do |name|
        combo.item Priest.title(name), name, icon: Priest.icon(name)
      end
      combo.value = old_value || Priest::FREE_UNLOCKS[combo_index] # Default 2 will be picked, since they are always playable.
    end

    protected
    def update_level_picker
      old_level_value = @level_picker.value # Preserve the previous setting.
      @god_picker.clear
      @level_picker.clear
      Level::LEVELS.each do |level|
        @god_picker.item(level::GOD.to_s, level::GOD, icon: level::GOD.icon, enabled: level.unlocked?)
        @level_picker.item(level.to_s, level, icon: level.icon, enabled: level.unlocked?)
      end
      @level_picker.value = old_level_value if old_level_value
      # God will be selected based on the level.

      @god_picker.enabled = (God.unlocked_picking? and not client?)
    end

    protected
    def player_grid
      @ready_indicators = []
      @num_readies = 0

      grid num_columns: 3, padding: 0, spacing_v: 1, spacing_h: 3 do
        @player_names.each_with_index do |player_name, player_number|
          player_row player_name, player_number
        end
      end
    end

    protected
    def player_row(player_name, player_number)
      @player_sprite_combos ||= {}

      is_local = ((player_number == @player_number) or offline?)
      @player_sprite_combos[player_name] = combo_box enabled: is_local do
        subscribe :changed do |sender, name|
          enable_priest_options

          send_message(Message::UpdateLobby.new(:player, player_number, name)) unless offline?
        end
      end

      label player_name, align_v: :center

      if @network
        @ready_indicators << label(t.label.ready, padding_h: 2, padding_v: 1, align_v: :center, color: READY_COLOR, background_color: UNREADY_BACKGROUND_COLOR)
      else
        label ''
      end
    end

    public
    # Start a new game. Also called from Message::NewGame.
    def new_game(level, god)
      if @network
        # Turn off the ready indicators, in case we come back to this state.
        2.times {|i| update_ready(i, false) }
        @ready_button.value = false
      end

      priest_names = @player_sprite_combos.values.map do |combo|
        combo.value
      end

      push_game_state level.new(@network, god, @player_names, priest_names)
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
    def update_god(god)
      @god_picker.value = god
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