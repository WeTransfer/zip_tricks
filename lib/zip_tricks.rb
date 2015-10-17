require 'zip'
module ZipTricks
  VERSION = '2.1.1'
  
  # Require all the sub-components except myself
  Dir.glob(__dir__ + '/**/*.rb').each {|p| require p unless p == __FILE__ }
end
