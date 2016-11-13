module ZipTricks
  VERSION = '4.2.2'
  
  # Require all the sub-components except myself
  Dir.glob(__dir__ + '/**/*.rb').sort.each {|p| require p unless p == __FILE__ }
end
