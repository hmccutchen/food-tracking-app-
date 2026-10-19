# Meal Planner

A Rails 8.1 app for a home health nurse choosing meals for patients with food
restrictions. See `docs/PLAN.md` for the plan and `CLAUDE.md` for working notes.

## Signing in

There is one account, the nurse's. Sign-in uses Devise; there is no sign-up page
and the app sends no email.

On a server, the account is created on the first deploy from two environment
variables (in Railway: the **web** service, then **Variables**):

- `NURSE_EMAIL`: the email address to sign in with.
- `NURSE_PASSWORD`: the first password, 12 to 72 characters.

After that, change the password on the **Account** page (under **More**). Changing
`NURSE_PASSWORD` later does nothing on its own, so a password changed in the app
is never overwritten by a deploy.

**Forgot the password?** Set `NURSE_PASSWORD` to a new value and add
`NURSE_RESET_PASSWORD=1`, then deploy. The deploy log shows "Nurse password reset
from NURSE_PASSWORD". Sign in with the new password, then delete
`NURSE_RESET_PASSWORD`; while it is set, every deploy resets the password again.

In development, `bin/rails db:seed` creates `nurse@example.com` with the password
`change-me-please`.

## USDA foods

Food search uses USDA FoodData Central's Foundation Foods and SR Legacy
datasets. These come from USDA's bulk CSV downloads, not their API.

- **Locally:** unzip the two CSV downloads into `db/usda/` and run
  `bin/rails usda:import`.
- **On the server:** set `USDA_IMPORT=1` on the web service and deploy once. The
  server downloads the newest files from fdc.nal.usda.gov and imports them in
  the background. The deploy log ends with "USDA import finished: N foods on
  file". Then remove `USDA_IMPORT`. Running it again is safe and just
  refreshes the rows.
