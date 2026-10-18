class FoodsController < ApplicationController
  def index
    @query = params[:q].to_s.strip
    @foods = @query.present? ? Food.search(@query) : []
    @food_count = Food.count
  end
end
