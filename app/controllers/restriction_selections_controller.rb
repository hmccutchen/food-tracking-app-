# "Choose items": edit all of one kind of restriction for a patient at once.
class RestrictionSelectionsController < ApplicationController
  before_action :set_selection

  def edit
    @picker = RestrictionPicker.new
  end

  def update
    result = @selection.update(params.fetch(:node_ids, []))
    redirect_to @patient, notice: summary(result)
  end

  private

  def set_selection
    @patient = Current.user.patients.find(params[:patient_id])
    raise ActiveRecord::RecordNotFound unless Restriction.kinds.key?(params[:kind])

    @selection = RestrictionSelection.new(@patient, params[:kind])
  end

  def summary(result)
    return "#{@selection.heading}: no changes." unless result.changed?

    parts = []
    parts << "added #{result.added.to_sentence}" if result.added.any?
    parts << "removed #{result.removed.to_sentence}" if result.removed.any?
    "#{@selection.heading}: #{parts.join('; ')}."
  end
end
