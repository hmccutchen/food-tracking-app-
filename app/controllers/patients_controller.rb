class PatientsController < ApplicationController
  before_action :set_patient, only: %i[show edit update destroy]

  def index
    # display_name is encrypted (non-deterministic), so sort in Ruby.
    @patients = Current.user.patients.to_a.sort_by { |patient| patient.display_name.downcase }
  end

  def show
    @restriction = @patient.restrictions.build
  end

  def new
    @patient = Current.user.patients.build
  end

  def create
    @patient = Current.user.patients.build(patient_params)
    if @patient.save
      redirect_to @patient, notice: "Patient added."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @patient.update(patient_params)
      redirect_to @patient, notice: "Patient updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    # Patient row first, then its restrictions, as every restriction writer does.
    @patient.with_lock { @patient.destroy! }
    redirect_to patients_path, notice: "Patient removed.", status: :see_other
  end

  private

  def set_patient
    @patient = Current.user.patients.find(params[:id])
  end

  def patient_params
    params.expect(patient: %i[display_name notes])
  end
end
