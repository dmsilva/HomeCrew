# Sending HomeCrew to TestFlight

The `TestFlight` workflow (Actions › TestFlight › Run workflow) archives the app on GitHub's Macs and uploads it to App Store Connect. Signing is automatic: Xcode creates the certificates, identifiers (app, widgets, App Group, iCloud container) and profiles with an App Store Connect API key.

## One-time setup

1. **App Store Connect › Apps › +**: new iOS app, name "HomeCrew", bundle ID `com.dmsilva.homecrew`, SKU `homecrew`, primary language Portuguese (Portugal).
2. **App Store Connect › Users and Access › Integrations › App Store Connect API**: generate a team key with the **Admin** role, which is needed for automatic signing to register identifiers. Download the `.p8` file. It can only be downloaded once.
3. **GitHub › Settings › Secrets and variables › Actions**: add three secrets:
   - `ASC_KEY_ID`: the key ID;
   - `ASC_ISSUER_ID`: the issuer ID shown above the keys;
   - `ASC_KEY_P8`: the full contents of the `.p8` file.
4. **CloudKit Console** (icloud.developer.apple.com) › `iCloud.com.dmsilva.homecrew`: run the app once in the simulator or on a device with a development build, so the schema exists. Then use **Deploy Schema Changes** to Production. TestFlight builds use the Production environment, and without this step they fail to sync.
5. **Privacy policy**: publish `docs/privacy-policy.md` (for example with GitHub Pages from `/docs`) and paste the URL under App Information.
6. **App Privacy** in App Store Connect: answer "Data Not Collected". The developer collects nothing, and everything stays in the user's iCloud.

## Each build

Run the workflow. The build number is the workflow run number, so it always goes up. After processing (about 10 to 30 minutes), add the build to an internal testing group in TestFlight and invite the family by email.
