# Everything that talks to (or prepares for) an AI provider lives under Ai::.
# Only restriction terms ever go to a provider; patient names never do.
module Ai
end

# The shared error taxonomy (Ai::Error and its subclasses) lives in one file,
# ai/errors.rb, which Zeitwerk can't map class by class. Load it with the namespace.
Ai::Errors.name
