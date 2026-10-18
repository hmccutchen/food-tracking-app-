# "Suggest meals" on the Who's eating page. create queues SuggestMealsJob
# (ids only); show is what the "Finding meals…" placeholder polls when no
# websocket is available; recheck re-runs only the engine (never the AI).
class MealRequestsController < ApplicationController
  RECENT = 5

  before_action :set_meal_request, only: %i[show recheck]

  # The "Recent meal suggestions" frame on the Who's eating page. A separate,
  # network-only request, so meal results never sit in the offline cache.
  def index
    @meal_requests = Current.user.meal_requests.recent.includes(:meal_suggestions).limit(RECENT)
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

  private

  # Only the nurse's own requests; anyone else's is a 404.
  def set_meal_request
    @meal_request = Current.user.meal_requests.includes(:meal_suggestions).find(params[:id])
  end
end
