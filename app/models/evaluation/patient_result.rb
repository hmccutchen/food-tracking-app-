module Evaluation
  # The flags for one patient. Holds ids only, never names, so it can be logged
  # or shown next to AI-supplied data.
  PatientResult = Data.define(:patient_id, :profile_version, :flags) do
    def initialize(patient_id:, profile_version:, flags: [])
      super(patient_id:, profile_version:, flags: flags.uniq.freeze)
    end

    # The worst tier among flags that were not overridden.
    def tier = Tier.worst(active_flags.map(&:tier))

    def active_flags = flags.select(&:active?)
    def overridden_flags = flags.select(&:overridden)
    def no_flags? = active_flags.empty?
  end
end
