# frozen_string_literal: true

# Is used internally by Streamer to keep track of entries in the archive during writing.
# Normally you will not have to use this class directly
class ZipTricks::Streamer::Entry < Struct.new(:filename, :crc32, :compressed_size,
                                              :uncompressed_size, :storage_mode, :mtime,
                                              :use_data_descriptor, :local_header_offset, :bytes_used_for_local_header, :bytes_used_for_data_descriptor)
  def initialize(*)
    super
    filename.force_encoding(Encoding::UTF_8)
    @requires_efs_flag = !(begin
                             filename.encode(Encoding::ASCII)
                           rescue
                             false
                           end)
  end

  def total_bytes_used
    bytes_used_for_local_header + compressed_size + bytes_used_for_data_descriptor
  end

  # Set the general purpose flags for the entry. We care about is the EFS
  # bit (bit 11) which should be set if the filename is UTF8. If it is, we need to set the
  # bit so that the unarchiving application knows that the filename in the archive is UTF-8
  # encoded, and not some DOS default. For ASCII entries it does not matter.
  # Additionally, we care about bit 3 which toggles the use of the postfix data descriptor.
  def gp_flags
    flag = 0b00000000000
    flag |= 0b100000000000 if @requires_efs_flag # bit 11
    flag |= 0x0008 if use_data_descriptor        # bit 3
    flag
  end
end
