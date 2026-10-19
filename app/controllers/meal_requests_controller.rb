# "Suggest meals" on the Who's eating page. create queues SuggestMealsJob
# (ids only); show is what the "Finding meals…" placeholder polls when no
# websocket is available; recheck re-runs only the engine (never the AI);
# destroy and clear remove finished cards so the page doesn't keep growing.
class MealRequestsController < ApplicationController
  RECENT = 5

  before_action :set_meal_request, only: %i[show recheck destroy]

  # The "Recent meal suggestions" frame on the Who's eating page. A separate,
  # network-only request, so meal results never sit in the offline cache.
  def index
    @meal_requests = recent_meal_requests
  end

  def create
    ids = Array(params[:patient_ids]).compact_blank.filter_map { |id| Integer(id, exception: false) }
    patient_ids = Current.user.patients.where(id: ids).pluck(:id)
    @meal_request = Current.user.meal_requests.new(patient_ids: ids & patient_ids,
      request_text: params[:request_text].to_s.strip.presence)

    if @meal_request.save
      SuggestMealsJob.perform_later(Current.user.id, @meal_request.id)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to group_path(patient_ids: @meal_request.patient_ids) }
      end
    else
      redirect_to group_path(patient_ids: ids), notice: @meal_request.errors.full_messages.to_sentence
    end
  end

  def show
    render partial: "meal_requests/meal_request", locals: { meal_request: @meal_request }
  end

  def recheck
    @meal_request.recheck! if @meal_request.finished?
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(@meal_request, partial: "meal_requests/meal_request",
          locals: { meal_request: @meal_request })
      end
      format.html { redirect_to group_path(patient_ids: @meal_request.current_patient_ids) }
    end
  end

  # A card still finding meals stays: its job is about to write to it.
  def destroy
    @meal_request.destroy! if @meal_request.finished?
    respond_to do |format|
      format.turbo_stream { render_removed }
      format.html { redirect_to group_path(patient_ids: @meal_request.current_patient_ids), status: :see_other }
    end
  end

  # Removes every finished card; ones still finding meals stay.
  def clear
    Current.user.meal_requests.where.not(status: MealRequest::PENDING).destroy_all
    respond_to do |format|
      format.turbo_stream { render_removed }
      format.html { redirect_to group_path, status: :see_other }
    end
  end

  private

  # The list shows the RECENT newest cards, so after a removal it is redrawn
  # whole: older cards fill the freed slots and the empty state shows only
  # when nothing is left.
  def render_removed
    render turbo_stream: turbo_stream.replace("recent_meal_requests", partial: "meal_requests/recent",
      locals: { meal_requests: recent_meal_requests })
  end

  def recent_meal_requests
    Current.user.meal_requests.recent.includes(:meal_suggestions).limit(RECENT)
  end

  # Only the nurse's own requests; anyone else's is a 404.
  def set_meal_request
    @meal_request = Current.user.meal_requests.includes(:meal_suggestions).find(params[:id])
  end
end
