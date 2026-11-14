# Repository layout

Paths in this guide are relative to the repository root.

| Directory | Responsibility |
| --- | --- |
| `frontend/` | React application and Capacitor Android/iOS shells |
| `native-ios/` | Native SwiftUI application, Watch app, Widget extension, shared code and tests |
| `api/` | HTTP API, optional coach and server tests |
| `mcp/` | Optional MCP server and its tests |
| `website/` | Public project website |
| `catalogue/` | Exercise definitions, translations and licensed media |
| `assets/` | Repository banner, screenshots and social artwork |
| `deploy/` | Deployment configuration: `web/`, `kubernetes/`, `helm/`, `nix/` |
| `scripts/` | Cross-project generation, catalogue, media and CI tooling |
| `docs/` | User/operator guides; `dev/` for design notes; `native-ios/` for native feature documentation |
| `artifacts/` | Local build/QA evidence; `outputs/` contains local exports and task reports |
| `data/`, `coach-auth/` | Local runtime data and provider credentials; ignored by Git |

`docker-compose.yml` and `.env.example` remain at the root so `docker compose` keeps its standard entry point. CI and dependency tooling retain their required root configuration locations.

## Native resources

```text
native-ios/
  App/                       iPhone/iPad app sources and configuration
    Models/                  iPhone models
    Services/                iPhone services
    Views/                   iPhone views
  Watch/                     Watch app sources, configuration and platform assets
  Widgets/                   Widget and Live Activity extension
  Shared/                    Code and brand assets shared by targets
    Assets.xcassets/         BrandMark and BrandLogo; no exercise thumbnails
    Models/                  Training, Watch, Health and Live Activity data types
    Services/                Localization, Health and Live Activity services
    ViewModels/              Training content models and platform data adapters
    Views/                   Shared views, grouped by feature
      TrainingContent/       Common training content layout and summary views
      TrainingAction/        Training/rest action display
      Timer/                 Countdown views and display formatting
      Style/                 Shared training display style
      LiveActivity/          Live Activity layout and native Intent interaction
  Resources/                 iPhone assets, rule bundle, launch screen and licenses
    Assets.xcassets/         iOS AppIcon and AccentColor; exercise images download on demand
    Localization/
      Localizable.xcstrings  Shared interface translations
      OpenGYM/
        InfoPlist.xcstrings  iPhone system strings
      OpenGYMWatch/
        InfoPlist.xcstrings  Watch system strings
  Tests/                     OpenGYMTests target sources
  scripts/                   Native project/resource tooling
  OpenGYM.xcodeproj/
```

Exercise images and videos are fetched from the configured server and persisted under `Documents/workout-images/` and `Documents/workout-videos/`; neither is bundled with the native app. Icons and shared branding remain in asset catalogs.

Native interface translations live in `Resources/Localization/*.xcstrings` and are edited in Xcode; `native-ios/scripts/configure-localization.rb` maintains their Xcode target references.

## Common entry points

```sh
docker compose up -d --build
npm run dev --prefix frontend
npm test --prefix api
npm test --prefix frontend
npm test --prefix mcp
open native-ios/OpenGYM.xcodeproj
kubectl apply -k deploy/kubernetes/
helm lint deploy/helm
```

See [Nix deployment](NIX.md) for `deploy/nix/`, and [native development](../native-ios/README.md) for Xcode build commands.

Keep generated build products and exported reports under `artifacts/`. Existing tracked build evidence is retained; ignore rules prevent new untracked outputs from entering future commits.
