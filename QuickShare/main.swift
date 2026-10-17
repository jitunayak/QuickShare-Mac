//
//  main.swift
//  QuickShare
//
//  Explicit entry point. QuickShare is a menu bar-only app: its entire UI is
//  built in code, so it does not need a main nib to instantiate the app
//  delegate. Doing the bootstrap by hand keeps the protocol core and the app
//  buildable without Xcode's Interface Builder and avoids depending on a
//  compiled MainMenu.nib at runtime.
//

import Cocoa

let application=NSApplication.shared
let delegate=AppDelegate()
application.delegate=delegate
application.setActivationPolicy(.accessory)
application.run()
