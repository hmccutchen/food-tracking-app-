require "rails_helper"

RSpec.describe "PWA" do
  let(:user) { create(:user, email_address: "nurse.pwa@example.com") }
  let!(:patient) do
    create(:patient, user:, display_name: "Zelda Quimby").tap do |zelda|
      create(:restriction, patient: zelda, kind: :allergy, term: "sesame")
    end
  end

  describe "manifest" do
    it "is valid JSON with the install fields and both icons, and no patient data" do
      get "/manifest.json"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      manifest = JSON.parse(response.body)
      expect(manifest).to include("name" => "Meal Planner", "short_name" => be_present, "start_url" => "/group",
        "display" => "standalone", "theme_color" => be_present, "background_color" => be_present)
      sizes = manifest["icons"].map { |icon| icon["sizes"] }
      expect(sizes).to include("192x192", "512x512")
      manifest["icons"].each do |icon|
        path = Rails.public_path.join(icon["src"].delete_prefix("/"))
        expect(path).to exist
        expect(File.binread(path, 8)).to eq("\x89PNG\r\n\x1A\n".b)
      end
      expect(response.body).not_to include("Zelda", "sesame")
    end

    it "is linked from every page" do
      get new_session_path
      expect(response.body).to include(%(rel="manifest" href="/manifest.json"))
    end
  end

  describe "service worker" do
    it "is served as JavaScript with digested shell assets and no patient-identifying strings" do
      sign_in(user)
      get "/service-worker.js"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/javascript")
      body = response.body
      expect(body).to include('import * as policy from "/assets/pwa/cache_policy-')
      expect(body).to match(%r{"/assets/application-\h+\.css"})
      expect(body).to match(%r{"/assets/application-\h+\.js"})
      expect(body).to include('"/offline.html"', '"/icon-192.png"', '"/icon-512.png"')
      expect(body).not_to include("Zelda", "Quimby", "sesame", user.email_address, "patient_ids")
      shell_urls = JSON.parse(body[/const SHELL_URLS = (\[.*?\])/, 1])
      expect(shell_urls).to all(match(%r{\A/(assets/|icon-|offline\.html)}))
    end

    it "is reachable signed out (browsers re-check it without cookies)" do
      get "/service-worker.js"
      expect(response).to have_http_status(:ok)
    end
  end

  it "serves an offline page that explains saved lists expire" do
    expect(Rails.public_path.join("offline.html").read).to include("Saved lists expire after 24 hours")
  end

  describe "registration" do
    it "is only on signed-in pages, with the offline caching choice" do
      get new_session_path
      expect(response.body).not_to include('data-controller="pwa"')

      sign_in(user)
      get group_path(patient_ids: [ patient.id ])
      expect(response.body).to include('data-controller="pwa"', 'data-pwa-offline-caching-value="true"')
      expect(response.body).to include('data-controller="sign-out"')
    end

    it "puts the purge backstop on the sign-in page" do
      get new_session_path
      expect(response.body).to include('data-controller="purge"')
    end
  end

  describe "browser HTTP cache" do
    it "sends no-store on signed-in pages" do
      sign_in(user)
      [ group_path(patient_ids: [ patient.id ]), patients_path, patient_path(patient), settings_ai_path,
        settings_offline_path, foods_path ].each do |path|
        get path
        expect(response).to have_http_status(:ok)
        expect(response.headers["Cache-Control"]).to eq("no-store"), path
      end
    end

    it "sends no-store on frame requests for the avoid list, which are full pages" do
      sign_in(user)
      get group_path(patient_ids: [ patient.id ]), headers: { "Turbo-Frame" => "avoid_list" }
      expect(response.headers["Cache-Control"]).to eq("no-store")
      expect(response.body).to include("<nav", "List built at")
    end
  end

  describe "offline caching setting" do
    before { sign_in(user) }

    it "defaults on and shows the shared-device note" do
      expect(user.reload.offline_caching_enabled).to be(true)
      get settings_offline_path
      expect(response.body).to include(
        "Saved avoid lists contain restriction terms and patient names. Turn this off on shared devices."
      )
    end

    it "turns off and back on, and pages report the choice to the service worker" do
      patch settings_offline_path, params: { user: { offline_caching_enabled: "0" } }
      expect(response).to redirect_to(settings_offline_path)
      expect(user.reload.offline_caching_enabled).to be(false)
      follow_redirect!
      expect(response.body).to include('data-pwa-offline-caching-value="false"', "Offline saving is off")

      patch settings_offline_path, params: { user: { offline_caching_enabled: "1" } }
      expect(user.reload.offline_caching_enabled).to be(true)
    end

    it "requires sign-in" do
      delete session_path
      patch settings_offline_path, params: { user: { offline_caching_enabled: "0" } }
      expect(response).to redirect_to(new_session_path)
      expect(user.reload.offline_caching_enabled).to be(true)
    end
  end
end
