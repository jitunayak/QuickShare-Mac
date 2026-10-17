//
//  Preferences.swift
//  QuickShare
//
//  Lightweight preferences backed by UserDefaults, plus the settings window.
//

import SwiftUI
import Combine

final class AppSettings: ObservableObject {
	static let shared=AppSettings()

	private let defaults=UserDefaults.standard
	private enum Keys{
		static let autoAccept="autoAccept"
	}

	/// When enabled, incoming transfers are accepted without showing a prompt.
	@Published var autoAccept:Bool{
		didSet{ defaults.set(autoAccept, forKey: Keys.autoAccept) }
	}

	private init(){
		autoAccept=defaults.bool(forKey: Keys.autoAccept)
	}
}

struct PreferencesView: View {
	@ObservedObject var settings=AppSettings.shared

	var body: some View {
		VStack(alignment: .leading, spacing: 14){
			Text("QuickShare")
				.font(.title2).bold()

			Toggle(NSLocalizedString("Pref.AutoAccept", value: "Accept incoming transfers automatically", comment: ""), isOn: $settings.autoAccept)
			Text(NSLocalizedString("Pref.AutoAcceptHint", value: "When off, QuickShare shows a notification with Accept and Decline buttons for every transfer. Text you receive is always copied to your clipboard and links always open in your browser.", comment: ""))
				.font(.footnote)
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)

			Divider()

			VStack(alignment: .leading, spacing: 4){
				Text(String(format: NSLocalizedString("Pref.DeviceName", value: "Device name: %@", comment: ""), Host.current().localizedName ?? "Mac"))
				Text(NSLocalizedString("Pref.Visible", value: "This Mac is visible to everyone on your local network.", comment: ""))
			}
			.font(.footnote)
			.foregroundStyle(.secondary)

			Spacer(minLength: 0)
		}
		.padding(20)
		.frame(width: 420, height: 260, alignment: .topLeading)
	}
}

final class PreferencesWindowController {
	static let shared=PreferencesWindowController()

	private var window:NSWindow?

	func show(){
		if window==nil{
			let hosting=NSHostingController(rootView: PreferencesView())
			let w=NSWindow(contentViewController: hosting)
			w.title=NSLocalizedString("Pref.WindowTitle", value: "QuickShare Preferences", comment: "")
			w.styleMask=[.titled, .closable]
			w.isReleasedWhenClosed=false
			w.center()
			window=w
		}
		NSApp.activate(ignoringOtherApps: true)
		window?.makeKeyAndOrderFront(nil)
	}
}
