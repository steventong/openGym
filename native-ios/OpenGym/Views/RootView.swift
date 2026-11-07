//
//  RootView.swift
//  OpenGym
//
//  Created by Steven on 07/11/2026.
//

import SwiftUI

struct RootView: View {
    @Environment(GymStore.self) private var store

    var body: some View {
        @Bindable var store = store

        // Stable selection values also serve notifications, Live Activities and workout actions.
        TabView(selection: $store.selectedTab) {
            Tab(value: 0) {
                HomeView()
            } label: {
                Label("HOME", systemImage: "house")
                    .accessibilityIdentifier("tab-0")
            }

            Tab(value: 1) {
                PlanView()
            } label: {
                Label("PLAN", systemImage: "calendar")
                    .accessibilityIdentifier("tab-1")
            }

            Tab(value: 2) {
                WorkoutView()
            } label: {
                Label(
                    store.draft == nil
                        ? String(
                            localized: "START",
                            bundle: AppLanguage.bundle,
                            locale: AppLanguage.locale
                        )
                        : String(
                            localized: "WORKOUT_IN_PROGRESS",
                            bundle: AppLanguage.bundle,
                            locale: AppLanguage.locale
                        ),
                    systemImage: store.draft == nil
                        ? "play.fill"
                        : "figure.strengthtraining.traditional"
                )
                .accessibilityIdentifier("tab-workout")
            }
            .badge(store.localSaveError == nil ? nil : Text("!"))

            Tab(value: 3) {
                StatsView()
            } label: {
                Label("STATS", systemImage: "chart.bar.xaxis")
                    .accessibilityIdentifier("tab-3")
            }

            Tab(value: 4) {
                LibraryView()
            } label: {
                Label("EXERCISES", systemImage: "dumbbell")
                    .accessibilityIdentifier("tab-4")
            }
        }
        .id(store.coachIdentity)
        .background(GymTheme.background)
        .foregroundStyle(.white)
        .background {
            LocalSaveStatus()
        }
        .sheet(isPresented: $store.showSettings) {
            SettingsView()
        }
        .sheet(item: $store.selectedExercise) {
            ExerciseDetail(exercise: $0)
        }
        .alert(
            "openGym",
            isPresented: Binding(
                get: { store.error != nil },
                set: {
                    if !$0 {
                        store.error = nil
                    }
                }
            )
        ) {
            Button("GOT_IT", role: .cancel) {
                store.error = nil
            }
        } message: {
            Text(store.error ?? "")
        }
        .background {
            AppLifecycleObserver()
        }
        .onOpenURL { url in
            if url.scheme == "opengym", url.host == "workout" {
                WorkoutActivityDiagnostics.record("app.open_workout_link")
                store.selectedTab = 2
            }
        }
    }
}

#Preview {
    @Previewable @State var store = GymStore()

    RootView()
        .environment(store)
        .environment(\.locale, AppLanguage.locale)
        .preferredColorScheme(.dark)
        .tint(GymTheme.green)
}
