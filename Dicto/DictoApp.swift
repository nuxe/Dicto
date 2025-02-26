//
//  DictoApp.swift
//  Dicto
//
//  Created by Kush Agrawal on 2/25/25.
//

import SwiftUI

@main
struct DictoApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
