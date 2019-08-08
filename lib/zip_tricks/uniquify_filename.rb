module ZipTricks::UniquifyFilename

  # Makes a given filename unique by appending a (n) suffix
  # between just before the filename extension. So "file.txt" gets
  # transformed into "file (1).txt". The transformation is applied
  # repeatedly as long as the generated filename is present
  # in `while_included_in` object
  #
  # @param path[String] the path to make unique
  # @param while_included_in[#include?] an object that stores the list of already used paths
  # @return [String] the path as is, or with the suffix required to make it unique
  def self.call(path, while_included_in)
    return path unless while_included_in.include?(path)

    # we add (1), (2), (n) at the end of a filename before the filename extension,
    # but only if there is a duplicate
    copy_pattern = /\((\d+)\)$/
    parts = path.split('.')
    ext = if parts.last =~ /gz|zip/ && parts.size > 2
            parts.pop(2)
          elsif parts.size > 1
            parts.pop
          end
    fn_last_part = parts.pop

    duplicate_counter = 1
    loop do
      fn_last_part = if fn_last_part =~ copy_pattern
                       fn_last_part.sub(copy_pattern, "(#{duplicate_counter})")
                     else
                       "#{fn_last_part} (#{duplicate_counter})"
                     end
      new_path = (parts + [fn_last_part, ext]).compact.join('.')
      return new_path unless while_included_in.include?(new_path)
      duplicate_counter += 1
    end
  end
end
