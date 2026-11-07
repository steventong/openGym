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
| `localization/` | Shared translation source JSON and metadata |
| `assets/` | Repository banner, screenshots and social artwork |
| `deploy/` | Deployment configuration: `web/`, `kubernetes/`, `helm/`, `nix/` |
| `scripts/` | Cross-project generation, localization, catalogue, media and CI tooling |
| `docs/` | User/operator guides; `dev/` for design notes; `native-ios/` for native feature documentation |
| `artifacts/` | Local build/QA evidence; `outputs/` contains local exports and task reports |
| `data/`, `coach-auth/` | Local runtime data and provider credentials; ignored by Git |

`docker-compose.yml` and `.env.example` remain at the root so `docker compose` keeps its standard entry point. CI and dependency tooling retain their required root configuration locations.

## Native resources

```text
native-ios/
  OpenGym/                   Native app sources
    Models/                  iPhone models
    Services/                iPhone services
    Views/                   iPhone views
    Resources/               iPhone-only assets and generated rule bundle
    Watch/                   Watch app
    Widgets/                 Widget and Live Activity extension
  OpenGymTests/              Tests
  Shared/                    Code shared by targets
    Training/                Training UI and timing types, one primary type per file
    LiveActivity/            Shared Live Activity definitions and presentation
  Resources/
    Localization/
      Localizable.xcstrings  Shared interface translations
      OpenGym/
        InfoPlist.xcstrings  iPhone system strings
      OpenGymWatch/
        InfoPlist.xcstrings  Watch system strings
  scripts/                   Native project/resource tooling
  OpenGym.xcodeproj/
```

Translation source remains in the root `localization/` directory. `scripts/localization/generate-apple.mjs` generates the catalogs; `native-ios/scripts/configure-localization.rb` maintains their Xcode target references.

## Common entry points

```sh
docker compose up -d --build
npm run dev --prefix frontend
npm test --prefix api
npm test --prefix frontend
npm test --prefix mcp
npm run check:localization
open native-ios/OpenGym.xcodeproj
kubectl apply -k deploy/kubernetes/
helm lint deploy/helm
```

See [Nix deployment](NIX.md) for `deploy/nix/`, and [native development](../native-ios/README.md) for Xcode build commands.

Keep generated build products and exported reports under `artifacts/`. Existing tracked build evidence is retained; ignore rules prevent new untracked outputs from entering future commits.
