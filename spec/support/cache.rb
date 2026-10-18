# The test cache is a memory store (for the sign-in rate limit); start each
# example with it empty so counts never carry over.
RSpec.configure do |config|
  config.before { Rails.cache.clear }
end
