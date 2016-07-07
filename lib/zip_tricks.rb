require 'zip'
require 'very_tiny_state_machine'

module ZipTricks
  VERSION = '2.6.0'

  # Require all the sub-components except myself
  Dir.glob(__dir__ + '/**/*.rb').sort.each {|p| require p unless p == __FILE__ }
end
