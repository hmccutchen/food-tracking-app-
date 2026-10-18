# "Descriptor words": harmless modifiers ("diced", "fresh", "cups") the engine
# may skip in an ingredient phrase once the rest of it was recognized. Shared
# reference data, not patient data. Words are turned off rather than deleted,
# so reseeding never brings one back on.
class IngredientDescriptorsController < ApplicationController
  before_action :set_descriptor, only: %i[edit update]

  def index
    @descriptors = IngredientDescriptor.ordered
    @descriptor = IngredientDescriptor.new
  end

  def create
    @descriptor = IngredientDescriptor.new(descriptor_params)
    if @descriptor.save
      redirect_to ingredient_descriptors_path, notice: "Descriptor word added."
    else
      @descriptors = IngredientDescriptor.ordered
      render :index, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @descriptor.update(descriptor_params)
      redirect_to ingredient_descriptors_path, notice: "Descriptor word updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_descriptor
    @descriptor = IngredientDescriptor.find(params[:id])
  end

  def descriptor_params
    params.expect(ingredient_descriptor: %i[word active])
  end
end
