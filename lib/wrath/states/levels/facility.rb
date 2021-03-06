module Wrath
class Level < GameState
  class Facility < Level
    DEFAULT_TILE = Plastic

    GOD = Ai

    def create_objects
      super

      # Static objects.
      18.times { Block.create(stack: [1, 1, 1, 1, 2, 2, 3].sample) }

      (0...$window.width).step(9) do |x|
        Block.create(x: x + 4, y: 16, stack: 2)
      end
    end

    def random_tiles
      num_columns, num_rows, grid = super(DEFAULT_TILE)

      grid
    end
  end
end
end