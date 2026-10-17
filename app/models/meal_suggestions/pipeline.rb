module MealSuggestions
  # Suggest → evaluate → drop conflicts → retry. The AI supplies dishes and
  # ingredient lists only; Evaluation::Engine sets every tier, and nothing in
  # the AI's reply beyond dish / ingredients / prep_notes is ever read.
  #
  #   outcome = MealSuggestions::Pipeline.new(credential:, patients:, request: "soft dinner").call
  #   outcome.found?   # at least one meal without a conflict
  #   outcome.kept     # [Kept(suggestion, group_result, prep_notes, cross_contact)]
  #
  # Retry rules (at most 1 + max_retries attempts in all):
  # - Every meal from an attempt was a conflict, or the reply was malformed,
  #   or the provider was rate limited / timed out / failed: try again, sending
  #   every ingredient that blocked a meal so far as `rejected:`.
  # - Stop as soon as an attempt keeps at least one meal.
  # - Invalid key, quota and missing model never fix themselves: stop at once.
  class Pipeline
    NON_RETRYABLE = [ Ai::InvalidKeyError, Ai::QuotaExceededError, Ai::ModelMissingError ].freeze

    def initialize(credential:, patients:, request:, adapter: nil, max_retries: 2, count: 3)
      @credential = credential
      @patient_ids = Array(patients).map { |patient| patient.is_a?(Patient) ? patient.id : Integer(patient) }.uniq
      @request = request
      @adapter = adapter
      @max_retries = Integer(max_retries).clamp(0, 10)
      @count = count
    end

    def call
      avoid_list = AvoidList.build(@patient_ids)
      run = Run.new(terms: avoid_list.to_terms, redact: avoid_list.patient_names)

      (1..(@max_retries + 1)).each do |number|
        attempt(run, number)
        break if run.kept.any? || run.stop
      end

      Outcome.new(kept: run.kept.freeze, dropped: run.dropped.freeze, attempts: run.attempts.freeze,
        final_error: run.kept.empty? ? run.last_error : nil, profile_versions: avoid_list.profile_versions)
    end

    private

    Run = Struct.new(:terms, :redact, :kept, :dropped, :attempts, :rejected, :last_error, :stop, keyword_init: true) do
      def initialize(**)
        super
        self.kept = []
        self.dropped = []
        self.attempts = []
        self.rejected = []
      end
    end

    def attempt(run, number)
      rejected_sent = run.rejected.dup.freeze
      suggestions = suggester.suggest(terms: run.terms, request: @request, rejected: rejected_sent, count: @count,
        redact: run.redact).suggestions
      run.last_error = nil
      dropped_before = run.dropped.size
      suggestions.each { |suggestion| sort(run, suggestion) }
      run.attempts << Attempt.new(number:, rejected_sent:, status: :ok, error_class: nil, error_message: nil,
        meals_returned: suggestions.size, meals_dropped: run.dropped.size - dropped_before)
    rescue Ai::Error => e
      run.last_error = e
      run.stop = NON_RETRYABLE.any? { |klass| e.is_a?(klass) }
      status = e.is_a?(Ai::MalformedResponseError) ? :malformed : :error
      run.attempts << Attempt.new(number:, rejected_sent:, status:, error_class: e.class.name,
        error_message: e.plain_message, meals_returned: 0, meals_dropped: 0)
    end

    def sort(run, suggestion)
      result = engine.evaluate(suggestion.ingredients)
      if result.tier == Evaluation::Tier::CONFLICT
        blocking = result.blocking_ingredients
        run.rejected |= blocking
        run.dropped << Dropped.new(suggestion:, group_result: result, blocking_ingredients: blocking.freeze,
          reasons: result.conflicts.map(&:reason).uniq.freeze)
      else
        run.kept << Kept.new(suggestion:, group_result: result, prep_notes: prep_notes_for(suggestion),
          cross_contact: cross_contact)
      end
    end

    # Advisory only: computed after the tier is fixed and never fed back.
    def prep_notes_for(suggestion)
      PrepNotes.for(patients: @patient_ids, dish: suggestion.dish, ingredients: suggestion.ingredients,
        prep_notes: suggestion.prep_notes)
    end

    def cross_contact
      return @cross_contact if defined?(@cross_contact)

      @cross_contact = PrepNotes.cross_contact_line(@patient_ids)
    end

    def suggester = @suggester ||= MealSuggester.new(@credential, adapter: @adapter)
    def engine = @engine ||= Evaluation::Engine.new(@patient_ids)
  end
end
