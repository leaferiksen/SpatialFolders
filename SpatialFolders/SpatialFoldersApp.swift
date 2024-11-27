//
//  SpatialFoldersApp.swift
//  SpatialFolders
//
//  Created by Leaf Eriksen on 11/20/24.
//

import SwiftUI

@main
struct SpatialFoldersApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(directoryURL: URL(fileURLWithPath: NSHomeDirectory()))
        }
    }
}
