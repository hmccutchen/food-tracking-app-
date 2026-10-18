# Runs the fixed sample requests in config/meal_samples.yml through
# MealSuggestions::Pipeline against one or all providers, and reports how the
# engine filtered each provider's meals (`rake meals:samples[provider]`).
#
# Keys and models come from ENV only (MEAL_SAMPLES_<PROVIDER>_KEY and
# MEAL_SAMPLES_<PROVIDER>_MODEL); a key is never printed or written out. Every
# synthetic patient is created inside a transaction that is rolled back.
#
#   MealSamples::Runner.new.call("openai")
#   MealSamples::Runner.new(adapter_factory: ->(credential) { FakeAdapter.new }) # specs
module MealSamples
  class Runner
    UnknownProviderError = Class.new(ArgumentError)

    PROVIDER_CHOICES = [ *Ai::Providers.keys, "all" ].freeze
    TOP_UNRESOLVED = 25
    HEADERS = [ "Sample", "Attempts", "Returned", "Kept", "Dropped (conflict)", "Kept w/ unknown", "Drop rate",
                "Unknown rate", "Malformed", "Failed", "Seconds" ].freeze

    Row = Data.define(:sample, :attempts, :returned, :kept, :dropped, :kept_unknown, :unknown_flags, :ingredients,
      :malformed, :failed, :seconds, :note)
    ProviderRun = Data.define(:provider, :model, :rows)

    def initialize(adapter_factory: ->(credential) { Ai::Adapters.for(credential) }, env: ENV, out: $stdout,
                   samples_path: Rails.root.join("config/meal_samples.yml"),
                   report_dir: Rails.root.join("tmp/meal_samples"),
                   clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @adapter_factory = adapter_factory
      @env = env
      @out = out
      @samples_path = samples_path
      @report_dir = Pathname(report_dir)
      @clock = clock
      @unresolved = Hash.new(0)
    end

    # Returns the path of the Markdown report, or nil when no provider ran.
    def call(choice = "all")
      choice = choice.to_s.strip.downcase.presence || "all"
      unless PROVIDER_CHOICES.include?(choice)
        raise UnknownProviderError, "Unknown provider #{choice.inspect}. Use one of: #{PROVIDER_CHOICES.join(', ')}."
      end

      warn_if_no_taxonomy
      providers = choice == "all" ? Ai::Providers.keys : [ choice ]
      ready, missing = providers.partition { |provider| configured?(provider) }
      skipped = missing.map { |provider| skip_line(provider) }
      skipped.each { |line| @out.puts(line) }
      runs = ready.map { |provider| run_provider(provider) }
      if runs.empty?
        @out.puts("No providers ran.")
        return
      end

      runs.each { |run| @out.puts(text_section(run)) }
      @out.puts(unresolved_text)
      write_report(runs, skipped)
    end

    private

    def samples
      @samples ||= YAML.safe_load_file(@samples_path).fetch("samples")
    end

    def warn_if_no_taxonomy
      return if TaxonomyNode.exists?

      @out.puts("Warning: the taxonomy is empty (run bin/rails db:seed). Every ingredient will read as unknown.")
    end

    def env_name(provider, part) = "MEAL_SAMPLES_#{provider.upcase}_#{part}"

    def skip_line(provider)
      missing = %w[KEY MODEL].map { |part| env_name(provider, part) }.reject { |name| @env[name].to_s.strip.present? }
      "Skipping #{Ai::Providers.name_for(provider)}: set #{missing.join(' and ')} to run it."
    end

    def configured?(provider) = %w[KEY MODEL].all? { |part| @env[env_name(provider, part)].to_s.strip.present? }

    def run_provider(provider)
      key = @env[env_name(provider, "KEY")].to_s.strip
      model = @env[env_name(provider, "MODEL")].to_s.strip

      credential = ProviderCredential.new(provider:, api_key: key, key_last4: key.last(4), model:)
      rows = []
      ActiveRecord::Base.transaction(requires_new: true) do
        user = User.create!(email: "meal-samples-#{SecureRandom.hex(6)}@example.invalid",
          password: SecureRandom.hex(16))
        rows = samples.map { |sample| run_sample(user, credential, sample) }
        raise ActiveRecord::Rollback
      end
      ProviderRun.new(provider:, model:, rows:)
    end

    def run_sample(user, credential, sample)
      patients = Array(sample["patients"]).map { |profile| create_patient(user, profile) }
      started = @clock.call
      outcome = MealSuggestions::Pipeline.new(credential:, patients:, request: sample["request"].to_s,
        adapter: @adapter_factory.call(credential)).call
      row_for(sample["key"], outcome, @clock.call - started)
    rescue StandardError => e
      # Class name only: a message could carry provider details.
      Row.new(sample: sample["key"], attempts: 0, returned: 0, kept: 0, dropped: 0, kept_unknown: 0, unknown_flags: 0,
        ingredients: 0, malformed: 0, failed: 1, seconds: 0.0, note: "crashed (#{e.class.name})")
    end

    def create_patient(user, profile)
      patient = user.patients.create!(display_name: profile.fetch("label"), notes: profile["note"])
      Restriction.kinds.each_key do |kind|
        Array(profile[kind]).each { |term| patient.restrictions.create!(kind:, term:) }
      end
      patient
    end

    def row_for(sample, outcome, seconds)
      entries = outcome.kept + outcome.dropped
      entries.each { |entry| unknown_ingredients(entry).each { |phrase| @unresolved[phrase.downcase.squish] += 1 } }
      Row.new(sample:, attempts: outcome.attempts.size, returned: outcome.attempts.sum(&:meals_returned),
        kept: outcome.kept.size, dropped: outcome.dropped.size,
        kept_unknown: outcome.kept.count { |entry| unknown_ingredients(entry).any? },
        unknown_flags: entries.sum { |entry| unknown_ingredients(entry).size },
        ingredients: entries.sum { |entry| entry.suggestion.ingredients.size },
        malformed: outcome.attempts.count { |attempt| attempt.status == :malformed },
        failed: outcome.attempts.count { |attempt| attempt.status == :error },
        seconds:, note: outcome.final_error&.class&.name)
    end

    # Ingredients of one meal with an active unknown flag for any patient,
    # counted once each however many patients share the flag.
    def unknown_ingredients(entry)
      entry.group_result.patient_results.flat_map(&:active_flags)
        .select { |flag| flag.tier == Evaluation::Tier::UNKNOWN && flag.ingredient.present? }
        .map(&:ingredient).uniq
    end

    def totals(rows)
      sum = ->(attr) { rows.sum(&attr) }
      Row.new(sample: "TOTAL", attempts: sum.(:attempts), returned: sum.(:returned), kept: sum.(:kept),
        dropped: sum.(:dropped), kept_unknown: sum.(:kept_unknown), unknown_flags: sum.(:unknown_flags),
        ingredients: sum.(:ingredients), malformed: sum.(:malformed), failed: sum.(:failed),
        seconds: sum.(:seconds), note: nil)
    end

    def cells(row)
      sample = row.note ? "#{row.sample} (#{row.note})" : row.sample
      [ sample, row.attempts, row.returned, row.kept, row.dropped, row.kept_unknown, rate(row.dropped, row.returned),
        rate(row.unknown_flags, row.ingredients), row.malformed, row.failed, format("%.1f", row.seconds) ].map(&:to_s)
    end

    def rate(part, whole) = whole.zero? ? "-" : format("%.1f%%", 100.0 * part / whole)

    def heading(run) = "#{Ai::Providers.name_for(run.provider)} (model #{run.model})"

    def text_section(run)
      table = [ HEADERS, *run.rows.map { |row| cells(row) }, cells(totals(run.rows)) ]
      widths = HEADERS.each_index.map { |index| table.map { |line| line[index].length }.max }
      lines = table.map do |line|
        line.each_with_index.map { |cell, index| index.zero? ? cell.ljust(widths[index]) : cell.rjust(widths[index]) }
          .join("  ").rstrip
      end
      lines.insert(1, widths.map { |width| "-" * width }.join("  "))
      lines.insert(-2, lines[1])
      [ "", "== #{heading(run)} ==", *lines, "" ].join("\n")
    end

    def markdown_section(run)
      rows = [ *run.rows.map { |row| cells(row) }, cells(totals(run.rows)).tap { |line| line[0] = "**TOTAL**" } ]
      [ "## #{heading(run)}", "", md_line(HEADERS), md_line([ "---", *Array.new(HEADERS.size - 1, "---:") ]),
        *rows.map { |line| md_line(line) }, "" ].join("\n")
    end

    def md_line(cells) = "| #{cells.map { |cell| cell.gsub('|', '\|') }.join(' | ')} |"

    def top_unresolved = @unresolved.sort_by { |phrase, count| [ -count, phrase ] }.first(TOP_UNRESOLVED)

    def unresolved_text
      list = top_unresolved
      return "\nUnresolved ingredient phrases: none." if list.empty?

      width = list.map { |_, count| count.to_s.length }.max
      [ "", "Most common unresolved ingredient phrases (top #{TOP_UNRESOLVED}):",
        *list.map { |phrase, count| "  #{count.to_s.rjust(width)}  #{phrase}" } ].join("\n")
    end

    def write_report(runs, skipped)
      @report_dir.mkpath
      path = @report_dir.join("#{Time.current.strftime('%Y%m%d-%H%M%S')}.md")
      list = top_unresolved.map { |phrase, count| "| #{phrase.gsub('|', '\|')} | #{count} |" }
      body = [ "# Meal sample run, #{Time.current.utc.iso8601}", "", *skipped.map { |line| "- #{line}" },
               ("" if skipped.any?), *runs.map { |run| markdown_section(run) },
               "## Most common unresolved ingredient phrases (top #{TOP_UNRESOLVED})", "",
               *(list.any? ? [ "| Phrase | Count |", "| --- | ---: |", *list ] : [ "None." ]), "" ].compact
      path.write(body.join("\n"))
      @out.puts("Report written to #{display_path(path)}")
      path
    end

    def display_path(path)
      path.to_s.start_with?("#{Rails.root}/") ? path.relative_path_from(Rails.root) : path
    end
  end
end
