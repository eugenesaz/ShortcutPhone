# Releasing

Releases are built by `.github/workflows/release.yml` when a `v*.*.*` tag is pushed. It runs
`check.sh`, signs the app with the **ShortcutPhone Release** identity, zips it, and publishes a
GitHub release with the notes from `CHANGELOG.md`.

## Secrets (once)

| Secret | What | Made by |
|---|---|---|
| `RELEASE_IDENTITY_P12_BASE64`, `RELEASE_IDENTITY_PASSWORD` | Code-signing certificate | `make-signing-identity.sh --export` |
| `SPARKLE_PRIVATE_KEY` | Signs updates; matches `SUPublicEDKey` in `Resources/Info.plist` | `sparkle.sh generate-key` |

Keep private backups of all of them. Losing the certificate makes users grant Accessibility
again. Losing the Sparkle key means installed apps reject every future update, so users must
download a new version by hand.

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

## The update key (once)

```sh
./scripts/sparkle.sh generate-key /tmp/sp-release   # prints the public key
```

Put the printed public key in `Resources/Info.plist` as `SUPublicEDKey`, and the contents of
`/tmp/sp-release/sparkle-private-key.txt` in the `SPARKLE_PRIVATE_KEY` secret. The release
workflow refuses to publish if the two don't match.

## Each release

1. Add a `## [X.Y.Z] - YYYY-MM-DD` section at the top of `CHANGELOG.md`.
2. Run the relevant rows of [manual-test.md](manual-test.md) with a local build.
3. Commit, then tag and push:

   ```sh
   git tag vX.Y.Z
   git push origin main vX.Y.Z
   ```

4. When the workflow finishes, the release has the zip, its checksum and `appcast.xml`.
   Installed apps find it within a day, or right away with **Check for Updates…**. Update an
   installed copy that way and check that it relaunches with Accessibility still granted.

`./scripts/release.sh X.Y.Z` builds the same zip locally, signed with `CODESIGN_IDENTITY`
(default: your local identity).

## If a release is broken

Mark the GitHub release as a pre-release or delete it. The **Latest** link, and with it the
update feed, then points to the previous version, so no more apps update to the broken one.
Apps that already updated get the fix with the next patch version, so ship one soon. Don't
reuse a tag.
