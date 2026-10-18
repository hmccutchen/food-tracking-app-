# "Choose items": edit all of one kind of restriction for a patient at once.
class RestrictionSelectionsController < ApplicationController
  before_action :set_selection

  def edit
    @picker = RestrictionPicker.new
  end

  def update
    result = @selection.update(params.fetch(:node_ids, []), expected_version: params.require(:profile_version))
    redirect_to @patient, notice: summary(result)
  rescue RestrictionSelection::Stale
    @patient.reload
    @picker = RestrictionPicker.new
    flash.now[:alert] = "#{@patient.display_name}'s profile changed in another window. Nothing was saved. " \
      "This list now shows the latest; tick again and save."
    render :edit, status: :conflict
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
