# "Custom items": foods or ingredients the nurse adds when they aren't in USDA
# or the built-in list, and marks can/cannot per patient. Only her own items are
# reachable here; seeded taxonomy nodes are never editable from these pages.
class CustomItemsController < ApplicationController
  before_action :set_item, only: %i[show edit update destroy marks]

  def index
    @items = Current.user.custom_items.includes(:parent, :aliases).order(:name)
  end

  def show
    @patients = Current.user.patients.to_a.sort_by { |patient| patient.display_name.downcase }
    @marks = @item.marks
  end

  def new
    @item = CustomItem.new(user: Current.user, name: params[:name].to_s.strip.first(200))
  end

  def create
    @item = CustomItem.new(user: Current.user, **item_params)
    if @item.save
      redirect_to custom_item_path(@item), notice: "Custom item added. Mark who can or cannot have it below."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    @item.assign_attributes(item_params)
    if @item.save
      redirect_to custom_item_path(@item), notice: "Custom item updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @item.destroy!
    redirect_to custom_items_path, notice: "Custom item deleted. Restrictions that used it now match by text only.",
      status: :see_other
  end

  # Per-patient can/cannot, written as ordinary restrictions.
  def marks
    @item.update_marks(params.fetch(:marks, {}).permit(*Current.user.patients.ids.map(&:to_s)).to_h)
    redirect_to custom_item_path(@item), notice: "Saved who can and cannot have it.", status: :see_other
  end

  private

  def set_item
    @item = CustomItem.new(user: Current.user, node: Current.user.custom_items.find(params[:id]))
  end

  def item_params
    params.expect(custom_item: %i[name ingredients_text parent_id aliases_text]).to_h.symbolize_keys
  end
end
