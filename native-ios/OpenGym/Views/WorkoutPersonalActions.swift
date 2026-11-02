import SwiftUI

struct WorkoutPersonalActions:View {
    @Environment(GymStore.self) private var store
    let record:WorkoutRecord
    var delete: () -> Void
    private var summary:String {
        let names = Dictionary((record.raw["entries"] as? [[String:Any]] ?? []).compactMap { entry -> (String,String)? in guard let id = entry["id"] as? String else{return nil};return (id,store.exercise(id)?.name ?? entry["n"] as? String ?? id) },uniquingKeysWith:{_,new in new})
        return (try? store.personalInfo("workoutText",["workout":record.raw,"names":names]))?["text"] as? String ?? ""
    }
    var body:some View {
        ShareLink(item:summary) {Label("分享",systemImage:"square.and.arrow.up")}
            .accessibilityIdentifier("share-history")
        Button(role:.destructive,action:delete) {Label("删除",systemImage:"trash")}
            .accessibilityIdentifier("delete-history")
    }
}
