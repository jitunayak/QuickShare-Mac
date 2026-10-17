//
//  Preferences.swift
//  QuickShare
//
//  Lightweight preferences backed by UserDefaults, plus the settings window.
//

import SwiftUI
import Combine
import AppKit
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

/// The folder received files are written to.
///
/// QuickShare is sandboxed, so a folder the user picks has to be remembered as
/// a security-scoped bookmark and opened for as long as the app runs —
/// otherwise the write fails at the far end of a transfer, long after the
/// panel that granted access has closed. Downloads is covered by the sandbox
/// entitlement, so it works without any of this and is the default.
enum ReceivedFiles {
	private static let bookmarkKey="receivedFilesBookmark"

	/// The user's Downloads folder, as a real path (it can be a symlink).
	static var defaultDirectory:URL {
		if let url=try? FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true){
			return url.resolvingSymlinksInPath()
		}
		return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
	}

	/// The folder the user picked, or `nil` while received files go to
	/// Downloads.
	private(set) static var customDirectory:URL?

	/// Whether received files go somewhere other than Downloads.
	static var isCustom:Bool {
		customDirectory != nil
	}

	/// The folder received files go to. Hand this to the connection manager.
	static var directory:URL {
		customDirectory ?? defaultDirectory
	}

	/// Resolves the saved folder and opens it for writing. Call once at launch,
	/// before any transfer can be accepted.
	///
	/// If the folder has gone away — deleted, renamed, or on a volume that is
	/// no longer mounted — the folder is forgotten and received files go back to
	/// Downloads, rather than every transfer failing at the end of the
	/// handshake.
	static func restore() {
		guard let data=defaults.data(forKey: bookmarkKey) else {return}
		var stale=false
		guard let url=try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) else {
			NSLog("QuickShare: could not reopen the chosen received-files folder; saving to Downloads instead")
			defaults.removeObject(forKey: bookmarkKey)
			return
		}
		// The scope has to be open before the folder can be tested, or the test
		// fails for a folder we are in fact allowed to use.
		url.startAccessingSecurityScopedResource()
		guard FileManager.default.isWritableFile(atPath: url.path) else {
			NSLog("QuickShare: \(url.path) is no longer writable; saving to Downloads instead")
			url.stopAccessingSecurityScopedResource()
			defaults.removeObject(forKey: bookmarkKey)
			return
		}
		customDirectory=url
		if stale, let refreshed=try? bookmarkData(for: url){
			// The folder moved. Keep using the URL we resolved and point the
			// stored bookmark at its new location.
			defaults.set(refreshed, forKey: bookmarkKey)
		}
	}

	/// Points received files at `url` and remembers access to it. Throws before
	/// changing anything if the folder cannot be written to.
	static func setDirectory(_ url:URL) throws {
		let data=try bookmarkData(for: url)
		// The panel that produced this URL has already granted access to it, so
		// it is writable here even though the scope below is only just opening.
		guard FileManager.default.isWritableFile(atPath: url.path) else {
			throw ReceivedFilesError.notWritable(url)
		}
		url.startAccessingSecurityScopedResource()
		// Close the previous folder only once the new one is open.
		let previous=customDirectory
		customDirectory=url
		defaults.set(data, forKey: bookmarkKey)
		if let previous=previous{
			previous.stopAccessingSecurityScopedResource()
		}
	}

	/// Goes back to the Downloads folder.
	static func reset() {
		customDirectory?.stopAccessingSecurityScopedResource()
		customDirectory=nil
		defaults.removeObject(forKey: bookmarkKey)
	}

	enum ReceivedFilesError:LocalizedError {
		case notWritable(URL)

		var errorDescription:String? {
			switch self{
			case .notWritable(let url):
				return String(format: NSLocalizedString("Pref.ReceivedFilesDenied", value: "QuickShare is not allowed to save files in “%@”. Pick another folder.", comment: ""), url.lastPathComponent)
			}
		}
	}

	private static var defaults:UserDefaults {
		UserDefaults.standard
	}

	private static func bookmarkData(for url:URL) throws -> Data {
		try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
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

	/// Where files received from other devices are saved.
	@Published private(set) var receivedFilesDirectory:URL=ReceivedFiles.directory

	/// Set when the last attempt to change the received files folder failed.
	@Published var receivedFilesError:String?

	/// The received files folder as shown in the preferences window, with the
	/// home directory shortened to `~`.
	var receivedFilesDisplayPath:String {
		let path=receivedFilesDirectory.path
		let home=FileManager.default.homeDirectoryForCurrentUser.path
		guard path.hasPrefix(home) else {return path}
		return "~"+path.dropFirst(home.count)
	}

	var receivedFilesIsCustom:Bool {
		ReceivedFiles.isCustom
	}

	private init(){
		autoAccept=defaults.bool(forKey: Keys.autoAccept)
		launchAtLogin=LoginItem.isEnabled
		// Default to visible: older installs have no stored value.
		visible=defaults.object(forKey: Keys.visible) as? Bool ?? true
		applyReceivedFilesDirectory()
	}

	/// Applies the current visibility preference to the connection manager.
	/// Call once at launch, after the preference has been read.
	func applyVisibility(){
		NearbyConnectionManager.shared.setVisible(visible)
	}

	/// Restores the saved received-files folder, if any, and hands it to the
	/// connection manager. Call once at launch.
	func applyReceivedFilesDirectory(){
		ReceivedFiles.restore()
		receivedFilesDirectory=ReceivedFiles.directory
		NearbyConnectionManager.shared.receivedFilesDirectory=ReceivedFiles.isCustom ? ReceivedFiles.directory : nil
	}

	/// Points received files at `url`, keeping access to it across launches.
	func setReceivedFilesDirectory(_ url:URL){
		do{
			try ReceivedFiles.setDirectory(url)
			receivedFilesError=nil
		}catch{
			NSLog("QuickShare: could not use \(url.path) for received files: \(error)")
			receivedFilesError=error.localizedDescription
			return
		}
		receivedFilesDirectory=ReceivedFiles.directory
		NearbyConnectionManager.shared.receivedFilesDirectory=ReceivedFiles.directory
	}

	/// Goes back to saving received files in Downloads.
	func resetReceivedFilesDirectory(){
		ReceivedFiles.reset()
		receivedFilesDirectory=ReceivedFiles.directory
		receivedFilesError=nil
		NearbyConnectionManager.shared.receivedFilesDirectory=nil
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

				receivedFilesSection

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
		.frame(width: 480, height: 660, alignment: .topLeading)
	}

	private var receivedFilesSection: some View {
		VStack(alignment: .leading, spacing: 8){
			Text(NSLocalizedString("Pref.ReceivedFiles", value: "Received files", comment: ""))
				.font(.headline)
			Text(NSLocalizedString("Pref.ReceivedFilesHint", value: "Files sent to this Mac are saved here. Text you receive goes to your clipboard and links open in your browser, so neither is saved as a file.", comment: ""))
				.font(.footnote)
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)

			HStack(spacing: 8){
				Image(systemName: "folder")
					.foregroundStyle(.secondary)
				Text(settings.receivedFilesDisplayPath)
					.lineLimit(1)
					.truncationMode(.middle)
					.help(settings.receivedFilesDirectory.path)
				Spacer(minLength: 8)
				if settings.receivedFilesIsCustom{
					Button(NSLocalizedString("Pref.ReceivedFilesReset", value: "Use Downloads", comment: "")){
						settings.resetReceivedFilesDirectory()
					}
				}
				Button(NSLocalizedString("Pref.ReceivedFilesChoose", value: "Choose…", comment: "")){
					chooseReceivedFilesFolder()
				}
			}

			if let error=settings.receivedFilesError{
				Text(error)
					.font(.footnote)
					.foregroundStyle(.red)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
	}

	private func chooseReceivedFilesFolder(){
		let panel=NSOpenPanel()
		panel.canChooseFiles=false
		panel.canChooseDirectories=true
		panel.canCreateDirectories=true
		panel.allowsMultipleSelection=false
		panel.directoryURL=settings.receivedFilesDirectory
		panel.message=NSLocalizedString("Pref.ReceivedFilesPanelMessage", value: "Choose where to save files sent to this Mac.", comment: "")
		panel.prompt=NSLocalizedString("Pref.ReceivedFilesPanelPrompt", value: "Save Here", comment: "")
		guard panel.runModal() == .OK, let url=panel.url else {return}
		settings.setReceivedFilesDirectory(url)
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
