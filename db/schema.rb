# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_18_195510) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "foods", force: :cascade do |t|
    t.bigint "fdc_id", null: false
    t.string "source", null: false
    t.string "data_type", null: false
    t.string "description", null: false
    t.string "category"
    t.text "ingredients_text"
    t.date "publication_date"
    t.datetime "imported_at", null: false
    t.jsonb "raw", default: {}, null: false
    t.bigint "taxonomy_node_id"
    t.string "match_type", default: "unresolved", null: false
    t.string "match_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["description"], name: "index_foods_on_description", opclass: :gin_trgm_ops, using: :gin
    t.index ["fdc_id"], name: "index_foods_on_fdc_id", unique: true
    t.index ["source"], name: "index_foods_on_source"
    t.index ["taxonomy_node_id"], name: "index_foods_on_taxonomy_node_id"
  end

  create_table "ingredient_descriptors", force: :cascade do |t|
    t.string "word", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["word"], name: "index_ingredient_descriptors_on_word", unique: true
  end

  create_table "meal_requests", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "patient_ids", default: [], null: false, array: true
    t.text "request_text"
    t.string "status", default: "queued", null: false
    t.string "provider"
    t.string "error_message"
    t.string "error_code"
    t.integer "attempts_count", default: 0, null: false
    t.text "blocking_conflicts"
    t.jsonb "profile_versions", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "created_at"], name: "index_meal_requests_on_user_id_and_created_at"
  end

  create_table "meal_suggestions", force: :cascade do |t|
    t.bigint "meal_request_id", null: false
    t.integer "position", null: false
    t.string "dish", null: false
    t.jsonb "ingredients", default: [], null: false
    t.jsonb "prep_notes", default: [], null: false
    t.boolean "kept", null: false
    t.string "tier", null: false
    t.text "result_json", null: false
    t.jsonb "profile_versions", default: {}, null: false
    t.datetime "evaluated_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["meal_request_id", "position"], name: "index_meal_suggestions_on_meal_request_id_and_position", unique: true
  end

  create_table "patients", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "display_name", null: false
    t.text "notes"
    t.integer "profile_version", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_patients_on_user_id"
  end

  create_table "prep_method_risks", force: :cascade do |t|
    t.bigint "prep_method_id", null: false
    t.bigint "taxonomy_node_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["prep_method_id", "taxonomy_node_id"], name: "index_prep_method_risks_on_prep_method_id_and_taxonomy_node_id", unique: true
    t.index ["prep_method_id"], name: "index_prep_method_risks_on_prep_method_id"
    t.index ["taxonomy_node_id"], name: "index_prep_method_risks_on_taxonomy_node_id"
  end

  create_table "prep_methods", force: :cascade do |t|
    t.string "name", null: false
    t.string "keywords", default: [], null: false, array: true
    t.text "risk", null: false
    t.text "lower_risk_method", null: false
    t.text "caveat", null: false
    t.integer "position", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_prep_methods_on_name", unique: true
  end

  create_table "provider_credentials", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "provider", null: false
    t.text "api_key", null: false
    t.string "key_last4", null: false
    t.string "model"
    t.jsonb "available_models", default: [], null: false
    t.datetime "validated_at"
    t.string "last_error_code"
    t.datetime "last_checked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "provider"], name: "index_provider_credentials_on_user_id_and_provider", unique: true
  end

  create_table "restrictions", force: :cascade do |t|
    t.bigint "patient_id", null: false
    t.string "kind", null: false
    t.string "term", null: false
    t.text "note"
    t.bigint "taxonomy_node_id"
    t.string "match_type", default: "unresolved", null: false
    t.string "match_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["kind"], name: "index_restrictions_on_kind"
    t.index ["patient_id"], name: "index_restrictions_on_patient_id"
    t.index ["taxonomy_node_id"], name: "index_restrictions_on_taxonomy_node_id"
  end

  create_table "taxonomy_aliases", force: :cascade do |t|
    t.bigint "taxonomy_node_id", null: false
    t.string "term", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["taxonomy_node_id"], name: "index_taxonomy_aliases_on_taxonomy_node_id"
    t.index ["term"], name: "index_taxonomy_aliases_on_term", unique: true
    t.index ["term"], name: "index_taxonomy_aliases_on_term_trgm", opclass: :gin_trgm_ops, using: :gin
  end

  create_table "taxonomy_memberships", force: :cascade do |t|
    t.bigint "node_id", null: false
    t.bigint "group_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["group_id", "node_id"], name: "index_taxonomy_memberships_on_group_id_and_node_id", unique: true
    t.index ["node_id"], name: "index_taxonomy_memberships_on_node_id"
  end

  create_table "taxonomy_nodes", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "kind", default: "ingredient", null: false
    t.bigint "parent_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "source", default: "seed", null: false
    t.bigint "created_by_id"
    t.text "ingredients_text"
    t.index ["created_by_id"], name: "index_taxonomy_nodes_on_created_by_id"
    t.index ["kind"], name: "index_taxonomy_nodes_on_kind"
    t.index ["name"], name: "index_taxonomy_nodes_on_name", unique: true
    t.index ["name"], name: "index_taxonomy_nodes_on_name_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["parent_id"], name: "index_taxonomy_nodes_on_parent_id"
    t.index ["slug"], name: "index_taxonomy_nodes_on_slug", unique: true
    t.index ["source"], name: "index_taxonomy_nodes_on_source"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "encrypted_password", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "active_provider"
    t.boolean "offline_caching_enabled", default: true, null: false
    t.datetime "remember_created_at"
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "foods", "taxonomy_nodes", on_delete: :nullify
  add_foreign_key "meal_requests", "users", on_delete: :cascade
  add_foreign_key "meal_suggestions", "meal_requests", on_delete: :cascade
  add_foreign_key "patients", "users"
  add_foreign_key "prep_method_risks", "prep_methods", on_delete: :cascade
  add_foreign_key "prep_method_risks", "taxonomy_nodes", on_delete: :cascade
  add_foreign_key "provider_credentials", "users", on_delete: :cascade
  add_foreign_key "restrictions", "patients", on_delete: :cascade
  add_foreign_key "restrictions", "taxonomy_nodes", on_delete: :nullify
  add_foreign_key "taxonomy_aliases", "taxonomy_nodes", on_delete: :cascade
  add_foreign_key "taxonomy_memberships", "taxonomy_nodes", column: "group_id", on_delete: :cascade
  add_foreign_key "taxonomy_memberships", "taxonomy_nodes", column: "node_id", on_delete: :cascade
  add_foreign_key "taxonomy_nodes", "taxonomy_nodes", column: "parent_id", on_delete: :nullify
  add_foreign_key "taxonomy_nodes", "users", column: "created_by_id", on_delete: :nullify
end
