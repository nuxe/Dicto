//
//  DictoApp.swift
//  Dicto
//
//  Created by Kush Agrawal on 2/25/25.
//

import SwiftUI
import Speech
import AppKit
import Carbon
import AVFoundation
import UserNotifications
import Combine

// MARK: - Main Application Entry Point
@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    
    var window: NSWindow!
    let appState = AppState()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the SwiftUI view that provides the window contents.
        let contentView = ContentView().environmentObject(appState)
        
        // Create the window and set the content view.
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.center()
        window.setFrameAutosaveName("Main Window")
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        window.title = "Dicto"
        
        // Set up menu
        setupMenu()
    }
    
    func setupMenu() {
        let mainMenu = NSMenu()
        
        // App menu
        let appMenu = NSMenu()
        let appMenuItem = NSMenuItem(title: "Dicto", action: nil, keyEquivalent: "")
        appMenuItem.submenu = appMenu
        
        appMenu.addItem(withTitle: "About Dicto", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: "Speech Recognition Settings", action: #selector(showSettings), keyEquivalent: ",")
        appMenu.addItem(settingsItem)
        
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Dicto", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        
        mainMenu.addItem(appMenuItem)
        
        // Edit menu
        let editMenu = NSMenu(title: "Edit")
        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editMenuItem.submenu = editMenu
        
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        
        mainMenu.addItem(editMenuItem)
        
        NSApplication.shared.mainMenu = mainMenu
    }
    
    @objc func showSettings() {
        appState.showSettingsView = true
    }
}

// MARK: - SpeechManager
class SpeechManager: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    static let shared = SpeechManager()
    
    @Published var isHotkeyEnabled: Bool = true
    @Published var isRecording = false
    
    private var speechRecognizer: SFSpeechRecognizer
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    private var eventMonitor: Any?
    
    override init() {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
        super.init()
        speechRecognizer.delegate = self
        setupHotkey()
        requestPermissions()
    }
    
    func changeRecognitionLocale(identifier: String) {
        guard let newRecognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier)) else {
            print("Locale not supported: \(identifier)")
            return
        }
        
        // Stop any ongoing recognition
        if isRecording {
            stopRecording()
        }
        
        speechRecognizer = newRecognizer
        speechRecognizer.delegate = self
    }
    
    private func setupHotkey() {
        // Monitor for global function key press
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            // Check if only the function key is pressed (Fn key with keycode 63)
            if event.keyCode == 63 && self?.isHotkeyEnabled == true {
                self?.toggleRecording()
            }
        }
    }
    
    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    print("Speech recognition authorized")
                default:
                    print("Speech recognition not authorized")
                }
            }
        }
        
        // Request notification permissions for macOS 10.14+
        if #available(macOS 10.14, *) {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error = error {
                    print("Error requesting notification permissions: \(error)")
                }
            }
        }
    }
    
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        if isRecording {
            return
        }
        
        // Cancel any ongoing recognition tasks
        if let recognitionTask = recognitionTask {
            recognitionTask.cancel()
            self.recognitionTask = nil
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let recognitionRequest = recognitionRequest else {
            print("Unable to create recognition request")
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            var isFinal = false
            
            if let result = result {
                isFinal = result.isFinal
                // Copy the transcribed text to clipboard
                self?.copyToClipboard(text: result.bestTranscription.formattedString)
            }
            
            if error != nil || isFinal {
                self?.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                
                self?.recognitionRequest = nil
                self?.recognitionTask = nil
                
                DispatchQueue.main.async {
                    self?.isRecording = false
                }
            }
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            DispatchQueue.main.async {
                self.isRecording = true
            }
            // Show feedback to user
            self.showRecordingFeedback(true)
        } catch {
            print("Audio engine failed to start: \(error)")
        }
    }
    
    private func stopRecording() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        DispatchQueue.main.async {
            self.isRecording = false
        }
        // Show feedback to user
        self.showRecordingFeedback(false)
    }
    
    private func copyToClipboard(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Optional: Paste text into active field
        pasteToActiveField(text: text)
    }
    
    private func pasteToActiveField(text: String) {
        // Simulate CMD+V to paste into active field
        let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true)  // 'V' key
        keyDownEvent?.flags = .maskCommand
        keyDownEvent?.post(tap: .cghidEventTap)
        
        let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false)
        keyUpEvent?.flags = .maskCommand
        keyUpEvent?.post(tap: .cghidEventTap)
    }
    
    private func showRecordingFeedback(_ isRecording: Bool) {
        // Display a visual indicator that recording has started/stopped
        if #available(macOS 11.0, *) {
            // Use newer notification API for newer macOS versions
            let notificationCenter = UNUserNotificationCenter.current()
            let content = UNMutableNotificationContent()
            content.title = isRecording ? "Recording Started" : "Recording Stopped"
            content.body = isRecording ? "Listening for speech..." : "Speech transcribed to clipboard"
            
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            notificationCenter.add(request)
        } else {
            // Legacy notification API for older macOS versions
            let notification = NSUserNotification()
            notification.title = isRecording ? "Recording Started" : "Recording Stopped"
            notification.informativeText = isRecording ? "Listening for speech..." : "Speech transcribed to clipboard"
            NSUserNotificationCenter.default.deliver(notification)
        }
    }
    
    deinit {
        if let eventMonitor = eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }
}

// MARK: - AppState
class AppState: ObservableObject {
    @Published var showSettingsView = false
    let speechManager = SpeechManager.shared
}

// MARK: - SettingsView
struct SettingsView: View {
    @ObservedObject var speechManager: SpeechManager
    @State private var isHotkeyEnabled = true
    @State private var selectedLanguage = "en-US"
    
    let availableLanguages = [
        "en-US": "English (US)",
        "en-GB": "English (UK)",
        "es-ES": "Spanish",
        "fr-FR": "French",
        "de-DE": "German",
        "ja-JP": "Japanese",
        "zh-Hans": "Chinese (Simplified)"
    ]
    
    var body: some View {
        Form {
            Section(header: Text("Hotkey Settings")) {
                Toggle("Enable Function Key Hotkey", isOn: $isHotkeyEnabled)
                    .onChange(of: isHotkeyEnabled) { newValue in
                        speechManager.isHotkeyEnabled = newValue
                    }
                Text("When enabled, press the Fn key to start speech recognition")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section(header: Text("Language")) {
                Picker("Recognition Language", selection: $selectedLanguage) {
                    ForEach(availableLanguages.keys.sorted(), id: \.self) { key in
                        Text(availableLanguages[key] ?? key).tag(key)
                    }
                }
                .onChange(of: selectedLanguage) { newValue in
                    speechManager.changeRecognitionLocale(identifier: newValue)
                }
            }
            
            Section(header: Text("About")) {
                Text("Dicto listens for your voice when you press the function key and transcribes your speech to text.")
                    .font(.caption)
                
                Button("Request Microphone Permissions") {
                    SFSpeechRecognizer.requestAuthorization { _ in }
                }
            }
        }
        .padding()
        .frame(width: 400, height: 300)
    }
}

// MARK: - ContentView
struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showSettingsSheet = false
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
                .foregroundColor(appState.speechManager.isRecording ? .red : .blue)
                .animation(.easeInOut, value: appState.speechManager.isRecording)
            
            Text(appState.speechManager.isRecording ? "Listening..." : "Press Fn key to start")
                .font(.title)
                .fontWeight(.medium)
            
            Text("Dicto will convert your speech to text and copy it to clipboard")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(action: {
                appState.speechManager.toggleRecording()
            }) {
                Text(appState.speechManager.isRecording ? "Stop Recording" : "Start Recording")
                    .fontWeight(.bold)
                    .padding()
                    .background(appState.speechManager.isRecording ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
            
            Button("Settings") {
                showSettingsSheet = true
            }
            .padding()
        }
        .padding()
        .frame(width: 300, height: 400)
        .sheet(isPresented: $showSettingsSheet) {
            SettingsView(speechManager: appState.speechManager)
        }
    }
} 