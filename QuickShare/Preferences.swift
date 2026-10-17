//
//  Preferences.swift
//  QuickShare
//
//  Lightweight preferences backed by UserDefaults, plus the settings window.
//

import SwiftUI
import Combine
import ServiceManagement
import QuickShareKit

/// Thin wrapper around `SMAppService` so the app can register itself as a login
/// item. `SMAppService` requires macOS 13; on older systems the feature is
/// reported as unavailable and the preference is hidden.
enum LoginItem {
	static var isSupported: Bool {
		if #available(macOS 13.0, *) { return true }
		return false
	}

	static var isEnabled: Bool {
		if #available(macOS 13.0, *) {
			return SMAppService.mainApp.status == .enabled
		}
		return false
	}

	static func setEnabled(_ enabled: Bool) {
		guard #available(macOS 13.0, *) else { return }
		do {
			if enabled {
				if SMAppService.mainApp.status != .enabled {
					try SMAppService.mainApp.register()
				}
			} else {
				if SMAppService.mainApp.status == .enabled {
					try SMAppService.mainApp.unregister()
				}
			}
		} catch {
			NSLog("QuickShare: could not \(enabled ? "enable" : "disable") launch at login: \(error)")
		}
	}
}

final class AppSettings: ObservableObject {
	static let shared=AppSettings()

	private let defaults=UserDefaults.standard
	private enum Keys{
		static let autoAccept="autoAccept"
		static let visible="visible"
	}

	/// When enabled, incoming transfers are accepted without showing a prompt.
	@Published var autoAccept:Bool{
		didSet{ defaults.set(autoAccept, forKey: Keys.autoAccept) }
	}

	/// When enabled, QuickShare starts automatically when the user logs in.
	@Published var launchAtLogin:Bool{
		didSet{ LoginItem.setEnabled(launchAtLogin) }
	}

	/// When enabled, this Mac advertises itself on the local network so other
	/// devices can see it and send to it.
	@Published var visible:Bool{
		didSet{
			defaults.set(visible, forKey: Keys.visible)
			NearbyConnectionManager.shared.setVisible(visible)
		}
	}

	private init(){
		autoAccept=defaults.bool(forKey: Keys.autoAccept)
		launchAtLogin=LoginItem.isEnabled
		// Default to visible: older installs have no stored value.
		visible=defaults.object(forKey: Keys.visible) as? Bool ?? true
	}

	/// Applies the current visibility preference to the connection manager.
	/// Call once at launch, after the preference has been read.
	func applyVisibility(){
		NearbyConnectionManager.shared.setVisible(visible)
	}
}

struct PreferencesView: View {
	@ObservedObject var settings=AppSettings.shared
	@ObservedObject var favourites=FavouritesStore.shared

	var body: some View {
		ScrollView{
			VStack(alignment: .leading, spacing: 14){
				Text("QuickShare")
					.font(.title2).bold()

				Toggle(NSLocalizedString("Pref.AutoAccept", value: "Accept incoming transfers automatically", comment: ""), isOn: $settings.autoAccept)
				Text(NSLocalizedString("Pref.AutoAcceptHint", value: "When off, QuickShare shows a notification with Accept and Decline buttons for every transfer. Text you receive is always copied to your clipboard and links always open in your browser.", comment: ""))
					.font(.footnote)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)

				Toggle(NSLocalizedString("Pref.LaunchAtLogin", value: "Launch QuickShare at login", comment: ""), isOn: $settings.launchAtLogin)
					.disabled(!LoginItem.isSupported)
				if LoginItem.isSupported{
					Text(NSLocalizedString("Pref.LaunchAtLoginHint", value: "QuickShare starts in the menu bar as soon as you log in, ready to receive files.", comment: ""))
						.font(.footnote)
						.foregroundStyle(.secondary)
						.fixedSize(horizontal: false, vertical: true)
				}else{
					Text(NSLocalizedString("Pref.LaunchAtLoginUnsupported", value: "Launch at login requires macOS 13 or later.", comment: ""))
						.font(.footnote)
						.foregroundStyle(.secondary)
						.fixedSize(horizontal: false, vertical: true)
				}

				Divider()

				Toggle(NSLocalizedString("Pref.VisibleToggle", value: "Visible to other devices", comment: ""), isOn: $settings.visible)
				Text(settings.visible
					? NSLocalizedString("Pref.VisibleHint", value: "Other devices on your network can see this Mac and send to it. Turn this off to hide QuickShare from your network.", comment: "")
					: NSLocalizedString("Pref.HiddenHint", value: "QuickShare is hidden: other devices cannot see this Mac or send to it. You can still send files and the clipboard from this Mac.", comment: ""))
					.font(.footnote)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)

				Divider()

				favouritesSection

				Divider()

				VStack(alignment: .leading, spacing: 4){
					Text(String(format: NSLocalizedString("Pref.DeviceName", value: "Device name: %@", comment: ""), Host.current().localizedName ?? "Mac"))
				}
				.font(.footnote)
				.foregroundStyle(.secondary)

				Spacer(minLength: 0)
			}
			.padding(20)
		}
		.frame(width: 480, height: 580, alignment: .topLeading)
	}

	private var favouritesSection: some View {
		VStack(alignment: .leading, spacing: 8){
			Text(NSLocalizedString("Pref.Favourites", value: "Favourite devices", comment: ""))
				.font(.headline)
			Text(NSLocalizedString("Pref.FavouritesHint", value: "Transfers from these devices are accepted automatically and silently — no notification is shown. You can also trust a device from its transfer notification with “Always Accept”.", comment: ""))
				.font(.footnote)
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)

			if favourites.names.isEmpty{
				Text(NSLocalizedString("Pref.NoFavourites", value: "No favourite devices yet.", comment: ""))
					.font(.footnote)
					.foregroundStyle(.secondary)
			}else{
				ForEach(favourites.names, id: \.self){ name in
					HStack(spacing: 8){
						Image(systemName: "star.fill")
							.foregroundStyle(.yellow)
						Text(name)
						Spacer(minLength: 8)
						Button{
							favourites.remove(name)
						}label:{
							Image(systemName: "trash")
						}
						.buttonStyle(.borderless)
						.help(NSLocalizedString("Pref.RemoveFavourite", value: "Remove from favourites", comment: ""))
					}
				}
			}

			HStack(spacing: 8){
				TextField(NSLocalizedString("Pref.AddFavouritePlaceholder", value: "Device name", comment: ""), text: $favourites.draftName)
					.textFieldStyle(.roundedBorder)
					.onSubmit(addFavourite)
				Button(NSLocalizedString("Pref.Add", value: "Add", comment: ""), action: addFavourite)
					.disabled(favourites.draftName.trimmingCharacters(in: .whitespaces).isEmpty)
			}
		}
	}

	private func addFavourite(){
		if favourites.add(favourites.draftName){
			favourites.draftName=""
		}
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
