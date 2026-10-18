require "rails_helper"

# Runs the real service worker in headless Chromium against the test server
# (127.0.0.1 counts as a secure context, so service workers are allowed).
RSpec.describe "Offline avoid lists (service worker)", js: true do
  let(:user) { create(:user) }
  let!(:patient) do
    user.patients.create!(display_name: "Ana Ruiz").tap { |ana| ana.restrictions.create!(kind: :allergy, term: "peanuts") }
  end
  let(:group_url) { "/group?patient_ids%5B%5D=#{patient.id}" }

  after do
    page.driver.browser.network.emulate_network_conditions(offline: false)
  rescue StandardError
    nil
  end

  def wait_for_worker
    expect(page).to have_css("#pwa[data-pwa-state='ready']", visible: :all, wait: 15)
  end

  # Entries in avoid-lists, or -1 when the cache does not exist. Checks first
  # so the probe itself never creates the cache.
  def avoid_list_urls
    page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1];
      (async () => {
        if (!(await caches.has("avoid-lists"))) return done(null)
        const cache = await caches.open("avoid-lists")
        done((await cache.keys()).map((request) => new URL(request.url).pathname + new URL(request.url).search))
      })().catch((error) => done("error: " + error))
    JS
  end

  def avoid_list_count
    urls = avoid_list_urls
    urls.nil? ? 0 : urls.length
  end

  def cache_names
    page.evaluate_async_script("const done = arguments[arguments.length - 1]; caches.keys().then(done)")
  end

  def eventually(timeout: 10)
    deadline = Time.current + timeout
    loop do
      result = yield
      return result if result || Time.current > deadline
      sleep 0.1
    end
  end

  def put_entry(path, body:, cached_at:)
    page.evaluate_async_script(<<~JS, path, body, cached_at.iso8601)
      const [path, body, cachedAt, done] = arguments;
      (async () => {
        const cache = await caches.open("avoid-lists")
        await cache.put(path, new Response(body, { headers: { "Content-Type": "text/html", "X-Cached-At": cachedAt } }))
        done(true)
      })()
    JS
  end

  def sweep
    page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1];
      navigator.serviceWorker.ready.then((registration) => {
        const channel = new MessageChannel()
        channel.port1.onmessage = (event) => done(event.data)
        registration.active.postMessage({ type: "sweep" }, [channel.port2])
      })
    JS
  end

  # Offline for both the page (navigator.onLine) and the service worker, which
  # is its own DevTools target with its own network.
  def go_offline
    browser = page.driver.browser
    worker = eventually { browser.service_workers.find { |target| target.url.include?("/service-worker.js") } }
    expect(worker).to be_present
    browser.attach_target(worker.id)
    worker.worker.network.emulate_network_conditions(offline: true)
    browser.network.emulate_network_conditions(offline: true)
  end

  def sign_in_and_open_group
    sign_in(user)
    expect(page).to have_content("Signed in as")
    wait_for_worker
    visit group_url
    expect(page).to have_css("#list_built_at", text: "List built at")
    wait_for_worker
    expect(eventually { avoid_list_count == 1 }).to be(true)
  end

  it "saves the viewed avoid list in avoid-lists, alongside only the app shell" do
    sign_in_and_open_group

    expect(avoid_list_urls).to eq([ group_url ])
    expect(cache_names).to contain_exactly("avoid-lists", a_string_matching(/\Aapp-shell-v\d+\z/))

    # Other signed-in pages stay network-only.
    visit patients_path
    visit settings_ai_path
    wait_for_worker
    expect(avoid_list_urls).to eq([ group_url ])
  end

  it "still signs out when the service worker can't be reached" do
    sign_in_and_open_group
    page.execute_script(<<~JS)
      navigator.serviceWorker.getRegistration = () => Promise.reject(new Error("storage blocked"))
    JS

    click_button "Sign out"

    expect(page).to have_current_path(new_session_path)
  end

  it "deletes avoid-lists when the nurse signs out" do
    sign_in_and_open_group

    click_button "Sign out"
    expect(page).to have_button("Sign in")
    expect(page).to have_css("#pwa_purge[data-purged='true']", visible: :all)

    expect(eventually { avoid_list_urls.nil? || avoid_list_urls.empty? }).to be(true)
    expect(cache_names).not_to include("avoid-lists")
  end

  it "purges a 25-hour-old entry on sweep and never serves an expired one, even offline" do
    sign_in_and_open_group
    stale_path = "/group?patient_ids%5B%5D=999999"
    put_entry(stale_path, body: "<p>STALE LIST</p>", cached_at: 25.hours.ago)
    expect(avoid_list_urls).to include(stale_path)

    expect(sweep).to include("type" => "swept", "removed" => 1)
    expect(avoid_list_urls).to eq([ group_url ])

    # Put it back and go offline: the worker shows the offline page instead.
    put_entry(stale_path, body: "<p>STALE LIST</p>", cached_at: 25.hours.ago)
    patient.update!(display_name: "Ana Renamed") # the server now says something else
    go_offline
    visit stale_path
    expect(page).to have_content("Saved lists expire after 24 hours")
    expect(page).to have_no_content("STALE LIST")

    # Control: the fresh copy is still served offline (the old name proves it
    # came from avoid-lists, not the server), with its age shown.
    visit group_url
    expect(page).to have_css("#list_built_at", text: "List built at")
    expect(page).to have_content("Ana Ruiz")
    expect(page).to have_no_content("Ana Renamed")
    # The network really is cut (the worker served this copy from avoid-lists),
    # but this headless Chromium's DevTools offline emulation does not flip
    # navigator.onLine, so flip that signal by hand to check the banner.
    page.execute_script(<<~JS)
      Object.defineProperty(navigator, "onLine", { configurable: true, get: () => false })
      window.dispatchEvent(new Event("offline"))
    JS
    expect(page).to have_css("#offline_banner", text: "You're offline — showing the list saved at")
  end

  it "empties avoid-lists when offline saving is turned off, and saves nothing new" do
    sign_in_and_open_group

    visit settings_offline_path
    expect(page).to have_content("Saved avoid lists contain restriction terms and patient names. Turn this off on shared devices.")
    uncheck "Save avoid lists for offline use"
    click_button "Save"
    expect(page).to have_content("Offline saving is off")
    wait_for_worker
    expect(eventually { avoid_list_count.zero? }).to be(true)

    visit group_url
    expect(page).to have_css("#list_built_at")
    wait_for_worker
    sleep 0.5
    expect(avoid_list_count).to eq(0)
  end
end
