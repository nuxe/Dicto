//
//  main.swift
//  Dicto
//
//  Created on the date of edit.
//

import AppKit

// This is the entry point of the application
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv) 