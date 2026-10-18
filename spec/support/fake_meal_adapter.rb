# Stands in for an Ai::Adapters class in pipeline and harness specs. Each call
# to #complete takes the next scripted reply: a Hash/Array (sent as JSON), a
# String (sent as is), an Ai::Error class (raised) or a Proc (called with the
# prompt). The last reply repeats once the script runs out.
class FakeMealAdapter
  attr_reader :prompts

  def self.meals(*meals) = { "meals" => meals }

  def self.meal(dish, *ingredients, prep_notes: [], **extra)
    { "dish" => dish, "ingredients" => ingredients, "prep_notes" => prep_notes }.merge(extra.stringify_keys)
  end

  def initialize(*replies, provider: "openai")
    @replies = replies
    @provider = provider
    @prompts = []
  end

  def calls = @prompts.size

  def complete(prompt)
    @prompts << prompt
    reply = @replies.fetch(@prompts.size - 1) { @replies.last }
    reply = reply.call(prompt) if reply.is_a?(Proc)
    raise reply.new(@provider) if reply.is_a?(Class) && reply <= Ai::Error

    reply.is_a?(String) ? reply : reply.to_json
  end
end
