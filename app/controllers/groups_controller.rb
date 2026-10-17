# "Who's eating?": pick patients, see their combined avoid list, and check a
# list of ingredients against them. The selection lives in the URL (so the page
# can be cached as is) and in the session (so coming back shows it again).
class GroupsController < ApplicationController
  SESSION_KEY = :group_patient_ids

  def show
    if !params.key?(:patient_ids) && session[SESSION_KEY].present?
      return redirect_to group_path(patient_ids: session[SESSION_KEY])
    end

    load_group
  end

  def check
    load_group
    @ingredients_text = params[:ingredients].to_s
    @result = Evaluation::Engine.new(@selected).evaluate(parse_ingredients(@ingredients_text))

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update("evaluation_result", partial: "evaluations/result",
          locals: { result: @result, patients: @names })
      end
      format.html { render :show }
    end
  end

  private

  # Only the nurse's own patients; other ids are ignored.
  def load_group
    @patients = Current.user.patients.to_a.sort_by { |patient| patient.display_name.downcase }
    ids = Array(params[:patient_ids]).compact_blank.filter_map { |id| Integer(id, exception: false) }
    @selected = @patients.select { |patient| ids.include?(patient.id) }
    session[SESSION_KEY] = @selected.map(&:id)
    @names = @selected.to_h { |patient| [ patient.id, patient.display_name ] }
    @avoid_list = AvoidList.build(@selected)
  end

  # One ingredient per line, or comma-separated.
  def parse_ingredients(text)
    text.split(/[\n,;]/).map(&:strip).compact_blank
  end
end
