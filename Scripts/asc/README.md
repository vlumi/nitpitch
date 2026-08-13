# App Store Connect tooling

Manage the App Store listing from the repo instead of the ASC UI — ported from
donpa's `Scripts/asc/`, minus its game-specific achievement parts.

- `listing.json` is the **single source of truth** for the listing text (name,
  subtitle, description, keywords, promo, URLs); edit it here, never in ASC.
  Its copy carries two commitments from ROADMAP § Toward 1.0: privacy wording
  that matches PRIVACY.md exactly (nothing leaves the device unless iCloud
  sync is opted into), and the interval/beat display advertised for **bowed**
  double stops only.
- `SCREENSHOTS.md` is the capture guide — what to shoot, staged how, in what
  order. `make shots` walks it interactively and captures for you.

## Setup (once)

Credentials reuse the release lane's: `Scripts/.asc-config` (Key ID + Issuer
ID) with the `.p8` in `~/.appstoreconnect/private_keys/` — nothing new to set
up. The Python venv bootstraps itself on first use (`run.sh`).

## Use

```sh
make asc-listing                # dry run: diff listing.json against ASC
make asc-listing-apply          # push the text

make shots PLATFORM=iphone      # guided capture (also ipad / mac)
make asc-screenshots            # dry run: show the upload plan
make asc-screenshots-apply      # replace + upload, in store order
```

Everything is dry-run by default; nothing writes without `--apply` (the
`-apply` targets). All of it needs the app record to exist in ASC first —
create the app (bundle id `fi.misaki.nitpitch`) in the ASC UI once, with an
editable version; the scripts refuse politely until then.
