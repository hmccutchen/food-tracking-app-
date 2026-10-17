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

ActiveRecord::Schema[8.1].define(version: 2026_10_18_000002) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "patients", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "display_name", null: false
    t.text "notes"
    t.integer "profile_version", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_patients_on_user_id"
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

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
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
    t.index ["kind"], name: "index_taxonomy_nodes_on_kind"
    t.index ["name"], name: "index_taxonomy_nodes_on_name", unique: true
    t.index ["name"], name: "index_taxonomy_nodes_on_name_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["parent_id"], name: "index_taxonomy_nodes_on_parent_id"
    t.index ["slug"], name: "index_taxonomy_nodes_on_slug", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "patients", "users"
  add_foreign_key "restrictions", "patients", on_delete: :cascade
  add_foreign_key "restrictions", "taxonomy_nodes", on_delete: :nullify
  add_foreign_key "sessions", "users"
  add_foreign_key "taxonomy_aliases", "taxonomy_nodes", on_delete: :cascade
  add_foreign_key "taxonomy_memberships", "taxonomy_nodes", column: "group_id", on_delete: :cascade
  add_foreign_key "taxonomy_memberships", "taxonomy_nodes", column: "node_id", on_delete: :cascade
  add_foreign_key "taxonomy_nodes", "taxonomy_nodes", column: "parent_id", on_delete: :nullify
end
