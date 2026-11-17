# Agent Instructions

Before starting any coding task, read and follow `~/.claude/skills/my-coding-principles/SKILL.md`.

This directory is a self-contained app. Do not read, import or reference files outside it: the
training rules live in `scripts/rules/`, the exercise catalogue in `Resources/catalogue.json`.
README.md describes the architecture, the data model and the build commands.

- User data lives in Core Data and syncs through iCloud. Every change to it goes through
  `GymStore.mutate` (App/Services/GymStore+Storage.swift); never write the database elsewhere.
- `Resources/web-rules.js` is generated. Edit `scripts/rules/` and run `npm run build:rules`.
- The Xcode project lists files explicitly. After adding or removing source files, update
  `OpenGYM.xcodeproj` (the scripts in `scripts/` use the `xcodeproj` Ruby gem).
- Exercise images and videos are licensed separately (Resources/NOTICE.txt). Do not open or
  describe them, and do not add media to the app bundle.
