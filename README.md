# Artist Tag Vault

Artist Tag Vault is an unofficial Flutter desktop tool for building a visual
catalog of how NovelAI interprets `artist:` tags. It applies one reusable preset,
generates a sample, previews it, and stores the image with reproducibility
metadata.

This project is independently implemented from NovelAI's official Image API
documentation. It is not affiliated with or endorsed by NovelAI.

## Current prototype

- macOS (Apple Silicon) first, Windows 10/11 x64 target
- automatic `artist:` prefix
- reusable model, steps, guidance, rescale, sampler, schedule, prompt, and UC
- separate aspect-ratio and resolution presets with resolved pixel dimensions
- API token test using `GET /user/subscription` (does not generate an image)
- live Subscription/Paid Anlas balances and V5 rechargeable allowance status
- token storage in macOS Keychain / Windows Credential Manager
- automatic PNG and JSON sidecar storage
- latest image preview and an Open Folder action

Samples use this future-gallery-friendly layout:

```text
Documents/ArtistTagVault/samples/
  <model-id>/
    <artist-name>/
      <UTC-timestamp>_seed-<seed>.png
      <UTC-timestamp>_seed-<seed>.json
```

## First local setup

Flutter platform runners are generated with your installed Flutter SDK. From the
repository root, run:

```bash
flutter create --platforms=macos,windows --org com.iutcoder .
git restore .
flutter pub get
flutter test
flutter run -d macos
```

The application identifier generated from this project is
`com.iutcoder.artistTagVault`. It can be changed before the first public release,
but changing it after release creates a different app identity and keychain scope.

### macOS signing and Keychain

`flutter create` writes Flutter's missing desktop runners. The following
`git restore .` keeps those new platform files while restoring any tracked source
or configuration that the template touched, including the checked-in entitlement
files. They enable outbound networking and Keychain access.
Open `macos/Runner.xcworkspace` in Xcode, select **Runner**, then choose a Personal
Team under **Signing & Capabilities**. Both DebugProfile and Release entitlements
must retain the `keychain-access-groups` entry; otherwise Keychain can return
security code `-34018`.

If `flutter run` says the app was built but could not be foregrounded, open the
generated `.app` once from Finder or run it from Xcode. The Flutter debug process
can remain attached even when macOS does not bring the window forward.

## API behavior

The app sends generation requests to:

- `POST https://image.novelai.net/ai/generate-image`
- `GET https://image.novelai.net/user/subscription` for token testing

Persistent tokens are sent only in the `Authorization: Bearer …` header. Do not
commit tokens, paste them into issue reports, or distribute a build containing a
token. Image generation may consume Anlas and remains subject to NovelAI's terms.

Official references:

- <https://image.novelai.net/docs/index.html>
- <https://image.novelai.net/docs/doc.json>
- <https://docs.novelai.net/en/image/models/>

## Project layout

```text
lib/src/models/       settings and preset data
lib/src/services/     official API client, persistence, prompt and sample storage
lib/src/widgets/      reusable glass UI surfaces
test/                 deterministic prompt behavior
```

Public classes and important decisions use Dart documentation comments (`///`)
and implementation comments (`//`) so the code can also serve as a learning
reference without annotating every obvious line.

## License

MIT. See [LICENSE](LICENSE).
