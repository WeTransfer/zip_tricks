# rubocop:disable Layout/IndentHeredoc

# A ZIP archive contains a flat list of entries. These entries can implicitly
# create directories when the archive is expanded. For example, an entry with
# the filename of "some folder/file.docx" will make the unarchiving application
# create a directory called "some folder" automatically, and then deposit the
# file "file.docx" in that directory. These "implicit" directories can be
# arbitrarily nested, and create a tree structure of directories. That structure
# however is implicit as the archive contains a flat list.
#
# This creates opportunities for conflicts. For example, imagine the following
# structure:
#
# * `something/` - specifies an empty directory with the name "something"
# * `something` - specifies a file, creates a conflict
#
# This can be prevented with filename uniqueness checks. It does get funkier however
# as the rabbit hole goes down:
#
# * `dir/subdir/another_subdir/yet_another_subdir/file.bin` - declares a file and directories
# * `dir/subdir/another_subdir/yet_another_subdir` - declares a file at one of the levels, creates a conflict
#
# The results of this ZIP structure aren't very easy to predict as they depend on the
# application that opens the archive. For example, BOMArchiveHelper on macOS will expand files
# as they are declared in the ZIP, but once a conflict occurs it will fail with "error -21". It
# is not very transparent to the user why unarchiving fails, and it has to - and can reliably - only
# be prevented when the archive gets created.
#
# Unfortunately that conflicts with another "magical" feature of ZipTricks which automatically
# "fixes" duplicate filenames - filenames (paths) which have already been added to the archive.
# This fix is performed by appending (1), then (2) and so forth to the filename so that the
# conflict is avoided. This is not possible to apply to directories, because when one of the
# path components is reused in multiple filenames it means those entities should end up in
# the same directory (subdirectory) once the archive is opened.
#
# The `PathSet` keeps track of entries as they get added using 2 Sets (cheap presence checks),
# one for directories and one for files. It will raise a `Conflict` exception if there are
# files clobbering one another, or in case files collide with directories.
class ZipTricks::PathSet
  class Conflict < StandardError
  end

  class FileClobbersDirectory < Conflict
  end

  class DirectoryClobbersFile < Conflict
  end

  def initialize
    @known_directories = Set.new
    @known_files = Set.new
  end

  # Adds a directory path to the set of known paths, including
  # all the directories that contain it. So, calling
  #    add_directory_path("dir/dir2/dir3")
  # will add "dir", "dir/dir2", "dir/dir2/dir3".
  #
  # @param path[String] the path to the directory to add
  # @return [void]
  def add_directory_path(path)
    path_and_ancestors(path).each do |parent_directory_path|
      if @known_files.include?(parent_directory_path)
        # Have to use the old-fashioned heredocs because ZipTricks
        # aims to be compatible with MRI 2.1+ syntax, and squiggly
        # heredoc is only available starting 2.3+
        error_message = <<ERR
The path #{parent_directory_path.inspect} which has to be added
as a directory is already used for a file.

The directory at this path would get created implicitly
to produce #{path.inspect} during decompresison.

This would make some archive utilities refuse to open
the ZIP.
ERR
        raise DirectoryClobbersFile, error_message
      end
      @known_directories << parent_directory_path
    end
  end

  # Adds a file path to the set of known paths, including
  # all the directories that contain it. Once a file has been added,
  # it is no longer possible to add a directory having the same path
  # as this would cause conflict.
  #
  # The operation also adds all the containing directories for the file, so
  #    add_file_path("dir/dir2/file.doc")
  # will add "dir" and "dir/dir2" as directories, "dir/dir2/dir3".
  #
  # @param file_path[String] the path to the directory to add
  # @return [void]
  def add_file_path(file_path)
    if @known_files.include?(file_path)
      error_message = <<ERR
The file at #{file_path.inspect} has already been included
in the archive. Adding it the second time would cause
the first file to be overwritten during unarchiving, and
could also get the archive flagged as invalid.
ERR
      raise Conflict, error_message
    end

    if @known_directories.include?(file_path)
      error_message = <<ERR
The path #{file_path.inspect} is already used for
a directory, but you are trying to add it as a file.

This would make some archive utilities refuse
to open the ZIP.
ERR
      raise FileClobbersDirectory, error_message
    end

    # Add all the directories which this file is contained in
    *dir_components, _file_name = non_empty_path_components(file_path)
    add_directory_path(dir_components.join('/'))

    # ...and then the file itself
    @known_files << file_path
  end

  # Tells whether a specific full path is already known to the PathSet.
  # Can be a path for a directory or for a file.
  #
  # @param path_in_archive[String] the path to check for inclusion
  # @return [Boolean]
  def include?(path_in_archive)
    @known_files.include?(path_in_archive) || @known_directories.include?(path_in_archive)
  end

  # Clears the contained sets
  # @return [void]
  def clear
    @known_files.clear
    @known_directories.clear
  end

  private

  def non_empty_path_components(path)
    path.split('/').reject(&:empty?)
  end

  def path_and_ancestors(path)
    path_components = non_empty_path_components(path)
    path_components.each_with_object([]) do |component, seen|
      seen << [seen.last, component].compact.join('/')
    end
  end
end
