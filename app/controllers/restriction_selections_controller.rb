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

  # The notice goes into the cookie session (4 KB), so a long change list is
  # summed up as counts rather than spelled out.
  SUMMARY_LIMIT = 300

  def summary(result)
    return "#{@selection.heading}: no changes." unless result.changed?

    named = summary_with(result.added.to_sentence, result.removed.to_sentence, result)
    return named if named.bytesize <= SUMMARY_LIMIT

    summary_with(helpers.pluralize(result.added.size, "item"), helpers.pluralize(result.removed.size, "item"), result)
  end

  def summary_with(added, removed, result)
    parts = []
    parts << "added #{added}" if result.added.any?
    parts << "removed #{removed}" if result.removed.any?
    "#{@selection.heading}: #{parts.join('; ')}."
  end
end
