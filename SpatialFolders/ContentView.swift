//
//  ContentView.swift
//  SpatialFolders
//
//  Created by Leaf Eriksen on 11/20/24.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - File System Observation

private class FileObserver {
    let directoryURL: URL
    private var fileDescriptor: Int32 = -1
    private var dispatchSource: DispatchSourceFileSystemObject?
    private let updateHandler: () -> Void

    init(directoryURL: URL, updateHandler: @escaping () -> Void) {
        self.directoryURL = directoryURL
        self.updateHandler = updateHandler
        startObserving()
    }

    deinit {
        stopObserving()
    }

    private func startObserving() {
        fileDescriptor = open(directoryURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        dispatchSource = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fileDescriptor, eventMask: .write, queue: .main)
        dispatchSource?.setEventHandler { [weak self] in
            self?.updateHandler()
        }
        dispatchSource?.setCancelHandler { [weak self] in
            guard let self = self else { return }
            close(self.fileDescriptor)
        }
        dispatchSource?.resume()
    }

    private func stopObserving() {
        dispatchSource?.cancel()
        dispatchSource = nil
    }
}

// MARK: - Content View

struct ContentView: View {
    let directoryURL: URL
    @State private var folderItems: [URL] = []
    @State private var error: AlertItem?
    @State private var isDropTargeted = false
    @State private var showReplaceConfirmation = false
    @State private var itemToReplace: URL?
    @State private var itemToMove: URL?
    @State private var fileObserver: FileObserver?
    @Environment(\.scenePhase) private var scenePhase

    private let pasteboardType = UTType(filenameExtension: "spatialdirectoryitem")!
    private let gridItemSize = CGSize(width: 100, height: 100)
    private let gridSpacing: CGFloat = 20
    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: gridItemSize.width), spacing: gridSpacing)]
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: gridSpacing) {
                ForEach(folderItems, id: \.self) { item in
                    FolderGridItem(item: item, itemAction: openItem)
                        .onDrop(of: [.fileURL, pasteboardType], isTargeted: .constant(false)) { providers, _ in
                            handleDrop(providers: providers, potentialDestinationURL: item)
                        }
                }
            }
            .padding()
        }
        .onAppear {
            loadFolderContents()
            fileObserver = FileObserver(directoryURL: directoryURL) { loadFolderContents() }
        }
        .navigationTitle(directoryURL.lastPathComponent)
        .frame(minWidth: 400, idealWidth: 600, maxWidth: .infinity, minHeight: 300, idealHeight: 500, maxHeight: .infinity)
        .onDisappear {
            fileObserver = nil
        }
        .alert(item: $error) { error in
            Alert(title: Text(error.title), message: Text(error.message))
        }
        .confirmationDialog("Replace Item?", isPresented: $showReplaceConfirmation, titleVisibility: .visible) {
            Button("Replace") {
                if let itemToReplace = itemToReplace, let itemToMove = itemToMove {
                    replaceItem(itemToMove, replacing: itemToReplace)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if let itemToReplace = itemToReplace {
                Text("An item named \"\(itemToReplace.lastPathComponent)\" already exists in this location. Do you want to replace it?")
            }
        }
        .onDrop(of: [.fileURL, pasteboardType], isTargeted: $isDropTargeted) { providers, location in
            guard findItemAtLocation(location) == nil else { return false }
            return handleDrop(providers: providers, potentialDestinationURL: nil, location: location)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor, lineWidth: 4)
            }
        }
        .onChange(of: scenePhase) { oldScenePhase, newScenePhase in
            if newScenePhase == .inactive {
                fileObserver = nil
            } else if newScenePhase == .active {
                 fileObserver = FileObserver(directoryURL: directoryURL) { loadFolderContents() }
            }
        }

    }

    // MARK: - Folder Content Loading

    private func loadFolderContents() {
        do {
            folderItems = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
                .sorted { a, b in
                    if a.isDirectory == b.isDirectory {
                        return a.lastPathComponent < b.lastPathComponent
                    }
                    return a.isDirectory
                }
        } catch {
            self.error = AlertItem(title: "Error", message: "Error loading folder contents: \(error.localizedDescription)")
        }
    }

    // MARK: - Item Actions

    private func openItem(item: URL) {
        if item.isDirectory {
            if item.pathExtension.lowercased() == "app" {
                NSWorkspace.shared.open(item)
            } else {
                openNewWindow(for: item)
            }
        } else {
            openFile(item)
        }
    }

    private func openNewWindow(for url: URL) {
        let newWindow = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 600, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        newWindow.center()
        newWindow.contentView = NSHostingView(rootView: ContentView(directoryURL: url))
        newWindow.title = url.lastPathComponent
        newWindow.makeKeyAndOrderFront(nil)
        newWindow.isReleasedWhenClosed = false
    }

    private func openFile(_ url: URL) {
        if !NSWorkspace.shared.open(url) {
            self.error = AlertItem(title: "Error", message: "Error opening file: \(url.lastPathComponent)")
        }
    }

    // MARK: - Drag and Drop

    private func handleDrop(providers: [NSItemProvider], potentialDestinationURL: URL?, location: CGPoint? = nil) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: URL.self) }) else { return false }

        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url = url else { return }
            DispatchQueue.main.async {
                self.itemToMove = url
                let destinationURL = potentialDestinationURL ?? self.directoryURL
                moveItem(url, to: destinationURL, location: location)
            }
        }
        return true
    }

    private func findItemAtLocation(_ location: CGPoint) -> URL? {
        folderItems.first(where: { item in
            guard let index = folderItems.firstIndex(of: item),
                  let itemFrame = getItemFrame(for: index),
                  itemFrame.contains(location) else { return false }
            return item.isDirectory && item.pathExtension.lowercased() != "app"
        })
    }

    private func getItemFrame(for index: Int) -> CGRect? {
        guard index >= 0 && index < folderItems.count else { return nil }

        let columns = Int((600 - 20) / (gridItemSize.width + gridSpacing))
        let row = index / columns
        let column = index % columns

        let x = CGFloat(column) * (gridItemSize.width + gridSpacing) + 10
        let y = CGFloat(row) * (gridItemSize.height + gridSpacing) + 10

        return CGRect(origin: CGPoint(x: x, y: y), size: gridItemSize)
    }

    private func moveItem(_ itemURL: URL, to destinationURL: URL, location: CGPoint? = nil) {
        let fileManager = FileManager.default
        let newDestinationURL: URL
        if let location = location {
            if let existingItemURL = findItemAtLocation(location) {
                newDestinationURL = existingItemURL.appendingPathComponent(itemURL.lastPathComponent)
            } else {
                newDestinationURL = destinationURL.appendingPathComponent(itemURL.lastPathComponent)
            }
        } else {
            newDestinationURL = destinationURL.isDirectory && destinationURL.pathExtension.lowercased() != "app"
            ? destinationURL.appendingPathComponent(itemURL.lastPathComponent)
            : destinationURL.deletingLastPathComponent().appendingPathComponent(itemURL.lastPathComponent)
        }

        guard itemURL != newDestinationURL else {
            print("Drag cancelled: item dropped in the same location.")
            resetMoveState()
            return
        }

        if fileManager.fileExists(atPath: newDestinationURL.path) {
            itemToReplace = newDestinationURL
            showReplaceConfirmation = true
        } else {
            performMove(itemURL, to: newDestinationURL)
        }
    }

    private func replaceItem(_ itemURL: URL, replacing existingItemURL: URL) {
        let fileManager = FileManager.default
        do {
            _ = try fileManager.replaceItemAt(existingItemURL, withItemAt: itemURL, backupItemName: nil, options: .usingNewMetadataOnly)
            loadFolderContents()
        } catch {
            self.error = AlertItem(title: "Error", message: "Error replacing item: \(error.localizedDescription)")
        }
        resetMoveState()
    }

    private func performMove(_ itemURL: URL, to destinationURL: URL) {
        let fileManager = FileManager.default
        do {
            try fileManager.moveItem(at: itemURL, to: destinationURL)
            loadFolderContents()
        } catch {
            self.error = AlertItem(title: "Error", message: "Error moving item: \(error.localizedDescription)")
        }
        resetMoveState()
    }

    private func resetMoveState() {
        itemToReplace = nil
        itemToMove = nil
        showReplaceConfirmation = false
    }
}

// MARK: - Folder Grid Item

struct FolderGridItem: View, Identifiable {
    let id = UUID()
    let item: URL
    var itemAction: (URL) -> Void

    private let pasteboardType = UTType(filenameExtension: "spatialdirectoryitem")!

    var body: some View {
        VStack {
            ItemIcon(item: item)
                .font(.system(size: 36))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.accentColor)
            Text(item.lastPathComponent)
                .lineLimit(1)
        }
        .frame(width: 100, height: 100)
        .onTapGesture {
            itemAction(item)
        }
        .onDrag {
            let provider = NSItemProvider(object: item as NSURL)
            provider.suggestedName = item.lastPathComponent
            return provider
        }
    }
}

// MARK: - Item Icon

private struct ItemIcon: View {
    let item: URL
    @State private var appIcon: NSImage?

    var body: some View {
        Group {
            if item.isDirectory && item.pathExtension.lowercased() == "app" {
                if let appIcon = appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "folder.fill")
                        .onAppear(perform: loadAppIcon)
                }
            } else {
                Image(systemName: item.iconName)
            }
        }
    }

    private func loadAppIcon() {
        appIcon = NSWorkspace.shared.icon(forFile: item.path)
    }
}

// MARK: - Alert Item

private struct AlertItem: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

// MARK: - URL Extensions

private extension URL {
    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    var iconName: String {
        isDirectory ? "folder.fill" : fileIcons[pathExtension.lowercased()] ?? "questionmark.text.page"
    }
}

// MARK: - File Icons

private let fileIcons: [String: String] = [
    "txt": "text.page", "md": "text.page",
    "rtf": "richtext.page", "pdf": "richtext.page", "doc": "richtext.page", "docx": "richtext.page",
    "epub": "book.pages", "mobi": "book.pages",
    "png": "photo", "jpg": "photo", "jpeg": "photo", "gif": "photo", "tiff": "photo", "heic": "photo",
    "mp3": "music.note", "wav": "music.note", "aac": "music.note", "m4a": "music.note", "m4b": "music.note", "aiff": "music.note", "wma": "music.note",
    "mp4": "play.rectangle", "mov": "play.rectangle", "avi": "play.rectangle", "mkv": "play.rectangle", "webm": "play.rectangle", "m4v": "play.rectangle", "flv": "play.rectangle", "wmv": "play.rectangle", "ogg": "play.rectangle",
    "zip": "archivebox", "rar": "archivebox", "7z": "archivebox", "tar": "archivebox", "gz": "archivebox", "bz2": "archivebox", "xz": "archivebox", "iso": "archivebox", "dmg": "archivebox",
    "xls": "tablecells", "xlsx": "tablecells",
    "ppt": "presentation", "pptx": "presentation",
    "swift": "chevron.left.forwardslash.chevron.right", "js": "chevron.left.forwardslash.chevron.right", "py": "chevron.left.forwardslash.chevron.right", "html": "chevron.left.forwardslash.chevron.right", "css": "chevron.left.forwardslash.chevron.right", "json": "chevron.left.forwardslash.chevron.right", "xml": "chevron.left.forwardslash.chevron.right"
]
