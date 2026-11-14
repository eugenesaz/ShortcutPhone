# Releasing

Releases are built by `.github/workflows/release.yml` when a `v*.*.*` tag is pushed. It runs
`check.sh`, signs the app with the **ShortcutPhone Release** identity, zips it, and publishes a
GitHub release with the notes from `CHANGELOG.md`.

## The release identity (once)

The app is signed with a self-signed certificate rather than an Apple Developer ID, so it isn't
notarized and users click **Open Anyway** on first launch. It still has to be the **same**
certificate for every release: macOS ties the Accessibility permission to it, and a new
certificate makes every user grant Accessibility again.

```sh
./scripts/make-signing-identity.sh --export /tmp/sp-release
base64 -i /tmp/sp-release/release-identity.p12 | pbcopy   # → secret RELEASE_IDENTITY_P12_BASE64
cat /tmp/sp-release/release-identity.password | pbcopy    # → secret RELEASE_IDENTITY_PASSWORD
```

Add both under the repo's **Settings › Secrets and variables › Actions**. Keep a private
backup of the two files (a password manager works), then `rm -r /tmp/sp-release`.

## Each release

1. Add a `## [X.Y.Z] - YYYY-MM-DD` section at the top of `CHANGELOG.md`.
2. Run the relevant rows of [manual-test.md](manual-test.md) with a local build.
3. Commit, then tag and push:

   ```sh
   git tag vX.Y.Z
   git push origin main vX.Y.Z
   ```

4. When the workflow finishes, download the zip from the release and open it on a Mac to check
   that it launches and still has its Accessibility grant from the previous version.

`./scripts/release.sh X.Y.Z` builds the same zip locally, signed with `CODESIGN_IDENTITY`
(default: your local identity).

## If a release is broken

Mark the GitHub release as a pre-release or delete it, so the **Latest** link points to the
previous version. Then fix the problem and ship a new patch version. Don't reuse a tag.
