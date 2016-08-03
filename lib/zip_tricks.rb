module ZipTricks
  VERSION = '3.0.0'
  
  # Require all the sub-components except myself
  Dir.glob(__dir__ + '/**/*.rb').sort.each {|p| require p unless p == __FILE__ }
end
