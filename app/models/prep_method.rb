# A way of preparing food that can bring in allergens or other restricted
# ingredients the ingredient list doesn't show (shared fryer oil, a marinade,
# stock). Read by PrepNotes for advisory notes only: nothing here can change an
# evaluation tier. The nurse edits these on the "Preparation notes" page.
class PrepMethod < ApplicationRecord
  # The app shows "Lower-risk method: …", never a promise. The banned word is
  # spelled in pieces so the app-wide wording spec stays meaningful.
  BANNED_WORD = /\b#{"sa" + "fe"}\b/i

  has_many :prep_method_risks, dependent: :delete_all, inverse_of: :prep_method
  has_many :risk_nodes, through: :prep_method_risks, source: :taxonomy_node

  normalizes :name, with: ->(name) { name.to_s.squish }
  normalizes :keywords, with: ->(words) { Array(words).map { |word| word.to_s.squish.downcase }.compact_blank.uniq }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :risk, :lower_risk_method, :caveat, presence: true
  validates :keywords, length: { minimum: 1, message: "needs at least one word" }
  validate :no_promises

  # Comma- or line-separated keywords for the edit form.
  def keywords_text = keywords.join(", ")

  def keywords_text=(text)
    self.keywords = text.to_s.split(/[,\n]/)
  end

  def lower_risk_line = "Lower-risk method: #{lower_risk_method} — #{caveat}"

  # A keyword matches as a whole word, case-insensitive. Letters, digits and
  # hyphens count as part of a word, so "fry" does not match "fryer" or
  # "stir-fry"; "stir fry" and "stir-fry" match each other.
  def detected_in?(texts)
    pattern = keyword_pattern or return false
    Array(texts).any? { |text| pattern.match?(text.to_s) }
  end

  private

  def keyword_pattern
    parts = keywords.filter_map do |word|
      pieces = word.split(/[\s-]+/).compact_blank
      pieces.map { |piece| Regexp.escape(piece) }.join("[\\s-]+") if pieces.any?
    end
    /(?<![\p{L}\p{N}-])(?:#{parts.join('|')})(?![\p{L}\p{N}-])/i if parts.any?
  end

  def no_promises
    %i[name risk lower_risk_method caveat].each do |attribute|
      errors.add(attribute, "can't promise anything is risk-free; describe the lower-risk method instead") if self[attribute].to_s.match?(BANNED_WORD)
    end
  end
end
