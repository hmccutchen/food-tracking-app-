# "Preparation notes": the nurse edits the methods, keywords, wording and risk
# nodes behind the advisory prep notes. Shared reference data, not patient data.
class PrepMethodsController < ApplicationController
  before_action :set_prep_method, only: %i[edit update]

  def index
    @prep_methods = PrepMethod.ordered.includes(:risk_nodes)
  end

  def edit
  end

  def update
    # Risk node ids are written as soon as they are assigned, so roll them back
    # with the rest when validation fails.
    saved = PrepMethod.transaction { @prep_method.update(prep_method_params) || raise(ActiveRecord::Rollback) }
    if saved
      redirect_to prep_methods_path, notice: "Preparation note updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_prep_method
    @prep_method = PrepMethod.find(params[:id])
  end

  def prep_method_params
    params.expect(prep_method: [ :name, :keywords_text, :risk, :lower_risk_method, :caveat, :position, :active,
      { risk_node_ids: [] } ])
  end
end
