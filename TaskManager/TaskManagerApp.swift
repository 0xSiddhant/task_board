//
//  TaskManagerApp.swift
//  TaskManager
//
//  Created by Siddhant Kumar on 08/08/26.
//

import SwiftUI
import CoreData

@main
struct TaskManagerApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
