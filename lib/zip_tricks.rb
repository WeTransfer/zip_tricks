# frozen_string_literal: true

# Require all the sub-components except myself
module ZipTricks
  Dir.glob(__dir__ + '/**/*.rb').sort.each { |p| require p unless p == __FILE__ }
end
