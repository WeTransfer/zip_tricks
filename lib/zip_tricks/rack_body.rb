# frozen_string_literal: true

# RackBody is actually just another use of the OutputEnumerator, since a Rack body
# object must support `#each` yielding successive binary strings.
class ZipTricks::RackBody < ZipTricks::OutputEnumerator
end
