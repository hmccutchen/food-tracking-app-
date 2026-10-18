class RestrictionsController < ApplicationController
  before_action :set_patient
  before_action :set_restriction, only: %i[edit update destroy]

  def create
    @restriction = @patient.restrictions.build(restriction_params)
    if @patient.with_lock { @restriction.save }
      respond_to do |format|
        format.turbo_stream { render_changes(new_restriction: @patient.restrictions.build) }
        format.html { redirect_to @patient, notice: "Restriction added." }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("new_restriction", partial: "restrictions/form",
            locals: { patient: @patient, restriction: @restriction }), status: :unprocessable_content
        end
        format.html { render_patient_with_errors }
      end
    end
  end

  def edit
  end

  def update
    if @patient.with_lock { @restriction.update(restriction_params) }
      respond_to do |format|
        format.turbo_stream { render_changes }
        format.html { redirect_to @patient, notice: "Restriction updated." }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(helpers.dom_id(@restriction), partial: "restrictions/form",
            locals: { patient: @patient, restriction: @restriction }), status: :unprocessable_content
        end
        format.html { render :edit, status: :unprocessable_content }
      end
    end
  end

  def destroy
    @patient.with_lock { @restriction.destroy! }
    respond_to do |format|
      format.turbo_stream { render_changes }
      format.html { redirect_to @patient, notice: "Restriction removed.", status: :see_other }
    end
  end

  private

  # Writes lock the patient row first, like RestrictionSelection#update, so
  # the two never interleave or take locks in a different order.
  def set_patient
    @patient = Current.user.patients.find(params[:patient_id])
  end

  def set_restriction
    @restriction = @patient.restrictions.find(params[:id])
  end

  def restriction_params
    params.expect(restriction: %i[kind term note manual_node_id])
  end

  # The list is re-rendered whole so a row moves when its kind changes.
  def render_changes(new_restriction: nil)
    @patient.reload
    streams = [
      turbo_stream.replace("restrictions", partial: "restrictions/list", locals: { patient: @patient }),
      turbo_stream.replace("profile_version", partial: "patients/profile_version", locals: { patient: @patient })
    ]
    if new_restriction
      streams << turbo_stream.replace("new_restriction", partial: "restrictions/form",
        locals: { patient: @patient, restriction: new_restriction })
    end
    render turbo_stream: streams
  end

  def render_patient_with_errors
    render "patients/show", status: :unprocessable_content
  end
end
