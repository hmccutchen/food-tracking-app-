module Evaluation
  # The flags for one patient. Holds ids only, never names, so it can be logged
  # or shown next to AI-supplied data.
  PatientResult = Data.define(:patient_id, :profile_version, :flags) do
    def initialize(patient_id:, profile_version:, flags: [])
      super(patient_id:, profile_version:, flags: flags.uniq.freeze)
    end

    def self.from_h(hash)
      hash = hash.to_h.symbolize_keys
      new(patient_id: Integer(hash.fetch(:patient_id)), profile_version: Integer(hash.fetch(:profile_version)),
        flags: Array(hash[:flags]).map { |flag| Flag.from_h(flag) })
    end

    def to_h
      { "patient_id" => patient_id, "profile_version" => profile_version, "flags" => flags.map(&:to_h) }
    end

    # The worst tier among flags that were not overridden.
    def tier = Tier.worst(active_flags.map(&:tier))

    def active_flags = flags.select(&:active?)
    def overridden_flags = flags.select(&:overridden)
    def no_flags? = active_flags.empty?
  end
end
