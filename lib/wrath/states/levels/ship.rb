module Wrath
class Level < GameState
  class Ship < Level
    DEFAULT_TILE = Planking

    GOD = Storm

    MAST_SPAWNS = [[-50, 0], [+50, 0]]

    def create_objects
      super

      # Static objects.
      MAST_SPAWNS.each do |pos|
        Mast.create(x: altar.x + pos[0], y: Margin::TOP + (($window.height - Margin::TOP) / 2) + pos[1])
      end

      (0...$window.width).step(8) do |x|
        Bulwalk.create(x: x + 4, y: 16) unless x.between?($window.width / 2 - 8, $window.width / 2)
        Bulwalk.create(x: x + 4, y: $window.height - 1)
      end
    end

    def random_tiles
      num_columns, num_rows, grid = super(DEFAULT_TILE)

      num_columns.times do |x|
        # Water at the top.
        grid[0][x] = grid[1][x] = SeaWater
      end

      grid
    end

    def update
      super

      if started?
        2.times { WaterDroplet.create(parent: self, position: [rand($window.width), rand($window.height), 1],
                                      velocity: [-0.5 + rand(0.99), 0, 0.2 + rand(0.3)], casts_shadow: false) }
      end
    end

    def create_altar
      Altar.create(x: $window.width / 2, y: Tile::HEIGHT * 3.5)
    end
  end
end
end