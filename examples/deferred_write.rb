# frozen_string_literal: true

require_relative '../lib/zip_tricks'

# Using deferred writes (when you want to "pull" from a Streamer)
# is also possible with ZipTricks.
#
# The OutputEnumerator class instead of Streamer is very useful for this
# particular purpose. It does not start the archiving immediately,
# but waits instead until you start pulling data out of it.
#
# Let's make a OutputEnumerator that writes a few files with random content. Note that when you create
# that body it does not immediately write the ZIP:
iterable = ZipTricks::Streamer.output_enum do |zip|
  (1..5).each do |i|
    zip.write_stored_file('random_%d04d.bin' % i) do |sink|
      warn "Starting on file #{i}...\n"
      sink << Random.new.bytes(1024)
    end
  end
end

warn "\n\nOutput using #each"

# Now we can treat the iterable as any Ruby enumerable object, since
# it supports #each yielding every binary string output by the Streamer.
# Only when we start using each() will the ZIP start generating. Just using
# each() like we do here runs the archiving procedure to completion. See how
# the output of the block within OutputEnumerator is interspersed with the stuff
# being yielded to each():
iterable.each do |_binary_string|
  $stderr << '.'
end

warn "\n\nOutput Enumerator returned from #each"

# We now have output the entire archive, so using each() again
# will restart the block we gave it. For example, we can user
# an Enumerator - via enum_for - to "take" chunks of output when
# we find necessary:
enum = iterable.each
15.times do
  _bin_str = enum.next  # Obtain the subsequent chunk of the ZIP
  $stderr << '*'
end

# ... or a Fiber

warn "\n\nOutput using a Fiber"
fib = Fiber.new do
  iterable.each do |binary_string|
    $stderr << '•'
    _next_iteration = Fiber.yield(binary_string)
  end
end
15.times do
  fib.resume # Process the subsequent chunk of the ZIP
end
