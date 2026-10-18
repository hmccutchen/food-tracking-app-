# A harmless modifier word ("diced", "fresh", "cups", "extra-virgin"). When an
# ingredient phrase is not recognized as a whole, the engine skips its
# whole-phrase unknown flag only if every word is either part of a recognized
# ingredient or an active descriptor (see docs/EVALUATION_RULES.md). The nurse
# edits these on the "Descriptor words" page.
class IngredientDescriptor < ApplicationRecord
  # Words that change what is in the food or hide what it is. They can never be
  # descriptors, so a phrase that uses them stays unknown.
  NEVER = [ "breaded", "battered", "fried", "crispy", "glazed", "marinated", "stuffed", "seasoned", "flavored",
            "flavoured", "sauce", "style", "mix", "blend", "imitation", "low sodium", "low-sodium" ].freeze

  normalizes :word, with: ->(word) { word.to_s.downcase.squish }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:word) }

  validates :word, presence: true, uniqueness: { case_sensitive: false }, length: { maximum: 40 },
    format: { with: /\A[\p{L}\p{N}' -]+\z/, message: "can only have letters, numbers, spaces, hyphens and apostrophes" }
  validate :not_a_never_word

  # Token sequence the engine matches against: "extra-virgin" → ["extra", "virgin"].
  def self.key(word) = word.to_s.downcase.split(/[\s-]+/).compact_blank.join(" ")

  # Keys of every active descriptor, for one evaluation.
  def self.active_keys = active.pluck(:word).to_set { |word| key(word) }

  private

  def not_a_never_word
    tokens = self.class.key(word).split
    banned = NEVER.find { |never| tokens.include?(never) || self.class.key(word) == self.class.key(never) }
    errors.add(:word, "'#{banned}' changes or hides what is in the food, so it can't be a descriptor") if banned
  end
end
