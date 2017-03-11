module ZipTricks
  # Require all the sub-components except myself
  Dir.glob(__dir__ + '/**/*.rb').sort.each {|p| require p unless p == __FILE__ }
end
