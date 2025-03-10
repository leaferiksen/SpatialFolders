# SpatialFolders
A macOS application designed to recreate the workflow of Finder in Classic Mac OS.
It makes many opinionated, non-optional changes, including single click to open files and folders and eventually a dedicated selection.
This was made by a young graphic designer with limited programming experience, and google's Gemini-exp-1121 model was used to help in the programming. If you are worried about the safety of your files, all the code that has been changed from Xcode's boilerplate is contained within ContentView.swift, SpacialFoldersApp.swift and SpatialFolders.entitlements. A swift programmer could read it all in about 10 minutes before trying it out.

## Instalation
Build in Xcode.

## Planned Features
### File
Rename
Quick Look
### Edit
Undo, redo
Cut, copy, paste
Selection Mode, inspired by Dolphin (KDE's file manager)
### View
Sort By 
### Other features
Opening folder aliases
Subfolder window restoration
Optionally showing hidden files

###tv# selection mode will be activated by clicking the spacebar. in that mode:
1. clicking an item would add it to the selection array, greyscale the sf symbol, and give it a background matching the  accent color. clicking it again would undo all of that.
    - Rename would become available in the File section of the menubar while just one item is selected. The option turns the item's name into a user input field, the content's of which becomes the item's new name once the enter key is pressed or the item is deselected
    - Multiple selected items can be dragged or opened at the same time
    - It should say selection mode in the title bar, along with the folder name that is there already
2. cmd+n should make a new folder
3. I should add a list view, cause it could come in handy 

#### Stuff I won't be building but you could add if you want
Anything else in classic Finder, because I don't have enough experience with it to know what I'm missing. If you code a solution to a missing feature, please push it my way! Just remember I only accept code written in SwiftUI since that is the lowest level language I know my way around.
I'll make small improvements to code quality over time, but I'm not primarily a programmer so the project would need outside help to significantly improve.
