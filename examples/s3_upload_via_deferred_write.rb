# frozen_string_literal: true

require_relative '../lib/zip_tricks'
require 'aws-sdk-s3'

# Using deferred writes (when you want to "pull" from a Streamer)
# can be used for doing a multipart S3 upload in chunks, since you will be
# receiving chunks of the ZIP larger or same size as the requested write buffer.
rng = Random.new
iterable = ZipTricks::Streamer.output_enum(write_buffer_size: 5 * 1024 * 1024) do |zip|
  12.times do |i|
    zip.write_stored_file('random_bits_%d04d.bin' % i) do |sink|
      sink << rng.bytes(1024 * 1024)
    end
  end
end

# Make this an S3 bucket of your choice
bucket = Aws::S3::Bucket.new('my-backups')

# Let's allocate our multipart upload
multipart_upload = bucket.object('big.zip').initiate_multipart_upload

# Now start iterating, which will begin the archiving procedure and start executing the block.
# As it proceeds you will receive at least 1 chunk, the first 2 chunks will be 5MB or larger.
iterable.each.with_index do |chunk, part_index_zero_based|
  # Part numbers are 1-based!
  multipart_upload.part(part_index_zero_based + 1).upload(body: chunk)
end

# And tell S3 to splice our parts
multipart_upload.complete(compute_parts: true)
