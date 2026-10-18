module MealSuggestions
  # status: :ok (the reply parsed), :malformed (unreadable reply) or :error.
  # error_class is the Ai::Error class name; error_message is its plain,
  # nurse-facing message (never a key, header or URL).
  Attempt = Data.define(:number, :rejected_sent, :status, :error_class, :error_message, :meals_returned,
    :meals_dropped) do
    def failed? = status != :ok
  end
end
