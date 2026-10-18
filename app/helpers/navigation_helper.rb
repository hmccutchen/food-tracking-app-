# Main navigation: which section the current page belongs to, so the nav can
# mark it with aria-current (and the "More" menu can show it holds the page).
module NavigationHelper
  SECTIONS = {
    "groups" => :group, "meal_requests" => :group,
    "patients" => :patients, "restrictions" => :patients,
    "foods" => :foods,
    "custom_items" => :custom_items,
    "settings/ai" => :ai_settings, "settings/ai_credentials" => :ai_settings,
    "settings/offline" => :offline,
    "prep_methods" => :prep_notes, "ingredient_descriptors" => :prep_notes
  }.freeze

  MORE_SECTIONS = %i[custom_items ai_settings offline prep_notes].freeze

  def nav_section
    SECTIONS[controller_path]
  end

  def nav_in_more_menu?
    MORE_SECTIONS.include?(nav_section)
  end

  # The link text stays plain (specs and screen readers read it as is); the
  # icon on the mobile tab bar comes from CSS.
  def nav_link_to(text, path, section)
    current = if current_page?(path) then "page"
    elsif nav_section == section then "true"
    end
    options = { class: "nav-link nav-link-#{section.to_s.dasherize}" }
    options[:aria] = { current: } if current
    link_to text, path, options
  end
end
