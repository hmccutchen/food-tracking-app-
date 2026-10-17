# RubyLLM's global config holds no API keys. Each call builds its own
# RubyLLM.context with only that nurse's key (see Ai::Adapters::Base), so one
# user's key can never reach another user's request.
RubyLLM.configure do |config|
  # WARN, never DEBUG: at DEBUG RubyLLM logs request and response bodies,
  # which carry the nurse's request text. Set explicitly so RUBYLLM_DEBUG in
  # the environment can't turn it back on.
  config.log_level = Logger::WARN
  config.log_stream_debug = false

  # One provider call should answer or fail plainly well inside a job's run.
  config.request_timeout = 45

  # No retries inside RubyLLM: our own retry loop (M9/M11) decides whether
  # another attempt is worth it, and counts it.
  config.max_retries = 0
end
