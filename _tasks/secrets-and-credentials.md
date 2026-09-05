# Secrets and credentials — deferred work

Written 5 Sep 2026. Everything here is a known, accepted shortcut rather than
something broken. Grouped because it is all one sitting's work and none of it
is worth doing piecemeal.

## Do these together

### 1. Rotate HOMEBREW_TAP_TOKEN

The current value was pasted into Slack on 5 Sep 2026 to get the cask bump
working. Small, trusted workspace, and the risk was accepted deliberately —
but it is in Slack history, its search index, and any integration with channel
access, so it should not be the long-term value.

What it is today:

- Ed's **personal** fine-grained PAT, so CI acts as him
- reaches `artisan-build/homebrew-tap` and `artisan-build/sonocles`
  (`ballast-cli` returns 404, so it is resource-scoped)
- `Contents: write` verified 5 Sep 2026 by creating and deleting
  `refs/heads/token-write-test` on the tap

What it should be: something owned by the org rather than a person, scoped to
the tap alone. The cask bump has no use for its `sonocles` access.

Two candidates, and a **deploy key is the tighter one** — it cannot reach
anything but the one repository, and it is not attached to a human at all. A
fine-grained org-owned PAT with `Contents: read and write` on `homebrew-tap`
is the simpler one. Either way the workflow needs no change: same secret name,
read the same way.

### 2. Promote the Apple secrets to organization level

Five secrets are set per-repo on `sonocles` and separately on `ballast-cli`.
Both repos sign with the same Developer ID and notarize through the same App
Store Connect key, so one org-level set should serve both:

    APPLE_CERT_P12_BASE64   APPLE_API_KEY_P8
    APPLE_CERT_PASSWORD     APPLE_API_KEY_ID
                            APPLE_API_ISSUER_ID

Use **`selected` visibility**, limited to the repos that actually ship signed
macOS binaries. Org-wide with `all` visibility would let any workflow in any
repo sign code as Artisan Build, which is a different order of problem from a
leaked API token — it is the company's notarization standing.

**Delete Ballast's repo-level copies once the org ones exist.** Repo secrets
take precedence over organization secrets of the same name, so leaving them
means Ballast quietly keeps using its own copies and the next certificate
rotation has to be done twice. That is the failure that looks like success.

There is no way to convert a repo secret to an org secret: GitHub never gives
a stored value back. Both need the plaintext re-entered, which is why this
pairs with re-exporting anyway.

Pair it with a GitHub **Environment** carrying required reviewers on the
release job, so signing runs on approved releases rather than any push that
reaches the workflow.

### 3. What is needed to do any of this

An `admin:org` scope on the gh token, or — narrower, and preferred — a
fine-grained PAT scoped to the `artisan-build` org with **Organization
permissions -> Secrets: read and write** and nothing else. Set an expiry.

## Separately: a date that matters

The **Developer ID Application certificate expires 1 February 2027.**
Renewing a certificate requires an active Developer Program membership. The
membership lapsed once already (some time after 7 August 2026, caught on
5 September when notarization started returning 403), so this is not
hypothetical. If it lapses again near that date, the certificate cannot be
renewed and every signed release stops being reproducible.

Note also that the renewal itself is not sufficient: a fresh Program License
Agreement has to be accepted in App Store Connect before the notary service
resumes, and until it is, the failure reads as a generic 403 rather than
anything about paperwork.

## Not a task, but worth knowing

`.signing/` holds the `.p12` and the App Store Connect `.p8`, and `.env` at
the repo root holds the `.p12` password. Both are gitignored. They are not
read by CI — CI reads repository secrets of the same names — they exist so a
signed build is possible locally and so the values can be re-derived without
hunting through Apple's website. See `.signing/README.md`.
