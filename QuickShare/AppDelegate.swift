//
//  AppDelegate.swift
//  QuickShare
//
//  Menu bar app for Google Quick Share (Nearby Share) on macOS.
//  - received text is copied straight to the clipboard
//  - received links open in the default browser
//  - incoming transfers are accepted from a notification (no PIN)
//  - files and the clipboard can be pushed back to Android
//

import Cocoa
import UserNotifications
import QuickShareKit

@objc(AppDelegate)
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSMenuDelegate, MainAppDelegate {
	private var statusItem:NSStatusItem?
	private var clipboardMenu:NSMenu?
	private var filesMenu:NSMenu?
	private var historyMenu:NSMenu?
	private var visibilityMenuItem:NSMenuItem?
	private var activeIncomingTransfers:[String:TransferInfo]=[:]
	private var lastTextReceivedFrom:RemoteDeviceInfo?
	/// Info about an outgoing transfer we started, keyed by device id, so the
	/// matching completion event can be turned into a history entry.
	private var pendingOutgoing:[String:PendingOutgoing]=[:]

	// MARK: - Lifecycle

	func applicationDidFinishLaunching(_ aNotification: Notification) {
		buildStatusMenu()

		let nc=UNUserNotificationCenter.current()
		nc.delegate=self
		nc.requestAuthorization(options: [.alert, .sound]) { granted, err in
			if !granted{
				DispatchQueue.main.async { self.showNotificationsDeniedAlert() }
			}
		}
		let incomingTransfersCategory=UNNotificationCategory(identifier: "INCOMING_TRANSFERS", actions: [
			UNNotificationAction(identifier: "ACCEPT", title: NSLocalizedString("Accept", comment: ""), options: []),
			UNNotificationAction(identifier: "ACCEPT_ALWAYS", title: NSLocalizedString("AcceptAlways", value: "Always Accept", comment: ""), options: []),
			UNNotificationAction(identifier: "DECLINE", title: NSLocalizedString("Decline", comment: ""))
		], intentIdentifiers: [])
		let infoCategory=UNNotificationCategory(identifier: "INFO", actions: [], intentIdentifiers: [])
		nc.setNotificationCategories([incomingTransfersCategory, infoCategory])

		NearbyConnectionManager.shared.mainAppDelegate=self
		NearbyConnectionManager.shared.onDevicesChanged={ [weak self] in
			self?.rebuildDeviceMenus()
		}
		NearbyConnectionManager.shared.onOutgoingTransferEvent={ [weak self] deviceID, event in
			self?.handleOutgoingEvent(deviceID: deviceID, event: event)
		}
		AppSettings.shared.applyVisibility()
	}

	func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
		statusItem?.isVisible=true
		return true
	}

	func applicationWillTerminate(_ aNotification: Notification) {
		UNUserNotificationCenter.current().removeAllDeliveredNotifications()
		// Withdraw our Bonjour record so we do not linger on other devices.
		NearbyConnectionManager.shared.setVisible(false)
	}

	func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
		return true
	}

	// MARK: - Menu bar

	private func buildStatusMenu(){
		let menu=NSMenu()
		menu.delegate=self

		let visible=NSMenuItem(title: NSLocalizedString("VisibleToEveryone", value: "Visible to everyone on this network", comment: ""), action: #selector(toggleVisibility(_:)), keyEquivalent: "")
		visible.target=self
		visible.state=AppSettings.shared.visible ? .on : .off
		menu.addItem(visible)
		visibilityMenuItem=visible

		let nameItem=NSMenuItem(title: String(format: NSLocalizedString("DeviceName", value: "This Mac: %@", comment: ""), Host.current().localizedName ?? "Mac"), action: nil, keyEquivalent: "")
		nameItem.isEnabled=false
		menu.addItem(nameItem)
		menu.addItem(NSMenuItem.separator())

		clipboardMenu=NSMenu()
		let clipboardItem=NSMenuItem(title: NSLocalizedString("SendClipboard", value: "Send Clipboard to", comment: ""), action: nil, keyEquivalent: "")
		clipboardItem.submenu=clipboardMenu
		menu.addItem(clipboardItem)

		filesMenu=NSMenu()
		let filesItem=NSMenuItem(title: NSLocalizedString("SendFiles", value: "Send Files to", comment: ""), action: nil, keyEquivalent: "")
		filesItem.submenu=filesMenu
		menu.addItem(filesItem)

		historyMenu=NSMenu()
		let historyItem=NSMenuItem(title: NSLocalizedString("History", value: "History", comment: ""), action: nil, keyEquivalent: "")
		historyItem.submenu=historyMenu
		menu.addItem(historyItem)

		menu.addItem(NSMenuItem.separator())
		let prefsItem=NSMenuItem(title: NSLocalizedString("Preferences", value: "Preferences…", comment: ""), action: #selector(openPreferences(_:)), keyEquivalent: ",")
		prefsItem.target=self
		menu.addItem(prefsItem)
		menu.addItem(NSMenuItem.separator())
		menu.addItem(NSMenuItem(title: NSLocalizedString("Quit", value: "Quit QuickShare", comment: ""), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

		statusItem=NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
		let icon=NSImage(named: "MenuBarIcon")
		icon?.isTemplate=true
		statusItem?.button?.image=icon
		statusItem?.button?.toolTip="QuickShare"
		statusItem?.menu=menu
		statusItem?.behavior = .removalAllowed
	}

	private func populateDeviceMenu(_ menu:NSMenu, selector:Selector){
		menu.removeAllItems()
		let devices=NearbyConnectionManager.shared.discoveredDevices
		if devices.isEmpty{
			let item=NSMenuItem(title: NSLocalizedString("NoDevices", value: "No devices found…", comment: ""), action: nil, keyEquivalent: "")
			item.isEnabled=false
			menu.addItem(item)
			return
		}
		for device in devices{
			let item=NSMenuItem(title: device.name, action: selector, keyEquivalent: "")
			item.representedObject=device.id
			item.target=self
			menu.addItem(item)
		}
	}

	private func rebuildDeviceMenus(){
		guard let clipboardMenu=clipboardMenu, let filesMenu=filesMenu else {return}
		populateDeviceMenu(clipboardMenu, selector: #selector(sendClipboardToDevice(_:)))
		populateDeviceMenu(filesMenu, selector: #selector(sendFilesToDevice(_:)))
	}

	func menuWillOpen(_ menu: NSMenu) {
		NearbyConnectionManager.shared.startDeviceDiscovery()
		rebuildDeviceMenus()
		rebuildHistoryMenu()
		updateVisibilityMenuState()
	}

	func menuDidClose(_ menu: NSMenu) {
		NearbyConnectionManager.shared.stopDeviceDiscovery()
	}

	// MARK: - Sending from this Mac

	@objc private func sendClipboardToDevice(_ sender:NSMenuItem){
		guard let deviceID=sender.representedObject as? String else {return}
		let pasteboard=NSPasteboard.general
		guard let text=pasteboard.string(forType: .string), !text.isEmpty else{
			showAlert(title: NSLocalizedString("ClipboardEmpty.Title", value: "Nothing to send", comment: ""), message: NSLocalizedString("ClipboardEmpty.Message", value: "The clipboard does not contain any text.", comment: ""))
			return
		}
		let trimmed=text.trimmingCharacters(in: .whitespacesAndNewlines)
		let isURL=trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
		guard NearbyConnectionManager.shared.sendText(text, isURL: isURL, toDeviceID: deviceID) else{
			showAlert(title: NSLocalizedString("DeviceGone.Title", value: "Device unavailable", comment: ""), message: NSLocalizedString("DeviceGone.Message", value: "That device is no longer reachable. Make sure Quick Share is open on it and try again.", comment: ""))
			return
		}
		pendingOutgoing[deviceID]=PendingOutgoing(
			kind: isURL ? .sentLink : .sentText,
			title: isURL ? linkSummary(text) : textPreview(text),
			payload: text,
			deviceName: deviceName(forID: deviceID))
	}

	@objc private func sendFilesToDevice(_ sender:NSMenuItem){
		guard let deviceID=sender.representedObject as? String else {return}
		let panel=NSOpenPanel()
		panel.canChooseFiles=true
		panel.canChooseDirectories=false
		panel.allowsMultipleSelection=true
		panel.prompt=NSLocalizedString("Send", comment: "")
		NSApp.activate(ignoringOtherApps: true)
		panel.begin { [weak self] response in
			guard response == .OK, !panel.urls.isEmpty else {return}
			let urls=panel.urls
			guard NearbyConnectionManager.shared.startOutgoingTransfer(deviceID: deviceID, delegate: nil, urls: urls) else{
				self?.showAlert(title: NSLocalizedString("DeviceGone.Title", value: "Device unavailable", comment: ""), message: NSLocalizedString("DeviceGone.Message", value: "That device is no longer reachable. Make sure Quick Share is open on it and try again.", comment: ""))
				return
			}
			let title: String
			if urls.count==1{
				title=urls[0].lastPathComponent
			}else{
				title=String(format: NSLocalizedString("History.NFiles", value: "%d files", comment: ""), urls.count)
			}
			self?.pendingOutgoing[deviceID]=PendingOutgoing(
				kind: .sentFile,
				title: title,
				payload: urls.map({$0.path}).joined(separator: "\n"),
				deviceName: self?.deviceName(forID: deviceID) ?? NSLocalizedString("UnknownDevice", value: "Unknown device", comment: ""))
		}
	}

	@objc private func openPreferences(_ sender:Any?){
		PreferencesWindowController.shared.show()
	}

	@objc private func toggleVisibility(_ sender:Any?){
		AppSettings.shared.visible.toggle()
		updateVisibilityMenuState()
	}

	private func updateVisibilityMenuState(){
		visibilityMenuItem?.state=AppSettings.shared.visible ? .on : .off
	}

	// MARK: - Outgoing transfer events

	private func handleOutgoingEvent(deviceID:String, event:OutgoingTransferEvent){
		switch event{
		case .finished:
			let pending=pendingOutgoing.removeValue(forKey: deviceID)
			if let pending=pending{
				HistoryStore.shared.record(kind: pending.kind, title: pending.title, payload: pending.payload, deviceName: pending.deviceName)
				rebuildHistoryMenu()
			}
			if pending?.kind.isFile == false{
				postInfoNotification(title: NSLocalizedString("ClipboardSent.Title", value: "Clipboard sent", comment: ""), body: NSLocalizedString("ClipboardSent.Body", value: "The clipboard was shared successfully.", comment: ""))
			}else{
				postInfoNotification(title: NSLocalizedString("Sent.Title", value: "Sent", comment: ""), body: NSLocalizedString("Sent.Body", value: "The transfer completed successfully.", comment: ""))
			}
		case .failed(let error):
			pendingOutgoing.removeValue(forKey: deviceID)
			postErrorNotification(errorMessage(for: error))
		case .established, .accepted, .progress:
			break
		}
	}

	// MARK: - MainAppDelegate (receiving)

	func obtainUserConsent(for transfer: TransferMetadata, from device: RemoteDeviceInfo) {
		// Favourite devices are trusted: accept silently, with no notification.
		if FavouritesStore.shared.isFavourite(device.name){
			NearbyConnectionManager.shared.submitUserConsent(transferID: transfer.id, accept: true)
			return
		}
		if AppSettings.shared.autoAccept{
			NearbyConnectionManager.shared.submitUserConsent(transferID: transfer.id, accept: true)
			postInfoNotification(title: NSLocalizedString("AutoAccepted.Title", value: "Transfer accepted", comment: ""), body: String(format: NSLocalizedString("AutoAccepted.Body", value: "Receiving from %@", comment: ""), device.name))
			return
		}

		let content=UNMutableNotificationContent()
		content.title="QuickShare"
		content.subtitle=device.name
		content.body=description(for: transfer, from: device)
		content.sound = .default
		content.categoryIdentifier="INCOMING_TRANSFERS"
		content.userInfo=["transferID": transfer.id, "deviceName": device.name]
		if #available(macOS 11.0, *){
			NDNotificationCenterHackery.removeDefaultAction(content)
		}
		let request=UNNotificationRequest(identifier: "transfer_"+transfer.id, content: content, trigger: nil)
		UNUserNotificationCenter.current().add(request)
		activeIncomingTransfers[transfer.id]=TransferInfo(device: device, transfer: transfer)
	}

	private func description(for transfer:TransferMetadata, from device:RemoteDeviceInfo)->String{
		if transfer.isTextMessage{
			return String(format: NSLocalizedString("SendingText", value: "%@ wants to send you text (it will be copied to your clipboard)", comment: ""), device.name)
		}
		if let link=transfer.textDescription{
			return String(format: NSLocalizedString("SendingLink", value: "%@ wants to send you a link: %@", comment: ""), device.name, link)
		}
		if transfer.files.count==1{
			return String(format: NSLocalizedString("SendingFile", value: "%@ wants to send you %@", comment: ""), device.name, transfer.files[0].name)
		}
		return String(format: NSLocalizedString("SendingFiles", value: "%@ wants to send you %d files", comment: ""), device.name, transfer.files.count)
	}

	func incomingTransfer(id: String, didFinishWith error: Error?) {
		guard let transfer=activeIncomingTransfers[id] else {return}
		defer { UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["transfer_"+id]) }
		if let error=error{
			postErrorNotification(errorMessage(for: error), title: String(format: NSLocalizedString("TransferError", value: "Failed to receive from %@", comment: ""), transfer.device.name))
		}
		activeIncomingTransfers.removeValue(forKey: id)
	}

	func incomingText(_ text: String, isURL: Bool, from device: RemoteDeviceInfo?) {
		lastTextReceivedFrom=device
		let deviceName=device?.name ?? unknownDeviceName
		if isURL{
			postInfoNotification(title: NSLocalizedString("LinkReceived.Title", value: "Link opened", comment: ""), body: text)
			HistoryStore.shared.record(kind: .receivedLink, title: linkSummary(text), payload: text, deviceName: deviceName)
		}else{
			let preview=textPreview(text)
			postInfoNotification(title: NSLocalizedString("TextReceived.Title", value: "Text copied to clipboard", comment: ""), body: preview)
			HistoryStore.shared.record(kind: .receivedText, title: preview, payload: text, deviceName: deviceName)
		}
		rebuildHistoryMenu()
	}

	func incomingFile(at url: URL, from device: RemoteDeviceInfo?) {
		postInfoNotification(title: NSLocalizedString("FileReceived.Title", value: "File received", comment: ""), body: url.lastPathComponent)
		HistoryStore.shared.record(kind: .receivedFile, title: url.lastPathComponent, payload: url.path, deviceName: device?.name ?? unknownDeviceName)
		rebuildHistoryMenu()
	}

	// MARK: - History menu

	private func rebuildHistoryMenu(){
		guard let historyMenu=historyMenu else {return}
		historyMenu.removeAllItems()
		let items=HistoryStore.shared.items
		if items.isEmpty{
			let empty=NSMenuItem(title: NSLocalizedString("History.Empty", value: "No recent transfers", comment: ""), action: nil, keyEquivalent: "")
			empty.isEnabled=false
			historyMenu.addItem(empty)
			return
		}
		for item in items{
			let menuItem=NSMenuItem(title: historyMenuTitle(for: item), action: #selector(historyItemSelected(_:)), keyEquivalent: "")
			menuItem.representedObject=item.id.uuidString
			menuItem.target=self
			menuItem.toolTip=historyTooltip(for: item)
			menuItem.image=NSImage(systemSymbolName: historySymbol(for: item.kind), accessibilityDescription: nil)
			historyMenu.addItem(menuItem)
		}
		historyMenu.addItem(NSMenuItem.separator())
		let clear=NSMenuItem(title: NSLocalizedString("History.Clear", value: "Clear History", comment: ""), action: #selector(clearHistory(_:)), keyEquivalent: "")
		clear.target=self
		historyMenu.addItem(clear)
	}

	@objc private func historyItemSelected(_ sender:NSMenuItem){
		guard let idString=sender.representedObject as? String,
		      let uuid=UUID(uuidString: idString),
		      let item=HistoryStore.shared.items.first(where: {$0.id==uuid}) else {return}
		switch item.kind{
		case .receivedText, .sentText:
			guard let text=item.payload else {return}
			let pasteboard=NSPasteboard.general
			pasteboard.clearContents()
			pasteboard.setString(text, forType: .string)
			postInfoNotification(title: NSLocalizedString("History.Copied", value: "Copied to clipboard", comment: ""), body: textPreview(text))
		case .receivedLink, .sentLink:
			guard let text=item.payload, let url=URL(string: text) else {return}
			NSWorkspace.shared.open(url)
		case .receivedFile, .sentFile:
			revealInFinder(item.payload)
		}
	}

	@objc private func clearHistory(_ sender:Any?){
		HistoryStore.shared.clear()
		rebuildHistoryMenu()
	}

	private func revealInFinder(_ payload:String?){
		guard let payload=payload else {return}
		let urls=payload.split(separator: "\n").map({URL(fileURLWithPath: String($0))})
			.filter({FileManager.default.fileExists(atPath: $0.path)})
		guard !urls.isEmpty else{
			showAlert(title: NSLocalizedString("History.FileGone.Title", value: "File not found", comment: ""), message: NSLocalizedString("History.FileGone.Message", value: "The file is no longer at its original location.", comment: ""))
			return
		}
		NSWorkspace.shared.activateFileViewerSelecting(urls)
	}

	private func historyMenuTitle(for item:HistoryItem)->String{
		let direction=item.kind.outgoing
			? NSLocalizedString("History.Sent", value: "Sent", comment: "")
			: NSLocalizedString("History.Received", value: "Received", comment: "")
		let what:String
		switch item.kind{
		case .receivedText, .sentText:
			what=String(format: NSLocalizedString("History.Text", value: "text “%@”", comment: ""), item.title)
		case .receivedLink, .sentLink:
			what=String(format: NSLocalizedString("History.Link", value: "link %@", comment: ""), item.title)
		case .receivedFile, .sentFile:
			what=item.title
		}
		let title="\(direction) \(what) — \(item.deviceName)"
		return title.count>90 ? String(title.prefix(90))+"…" : title
	}

	private func historyTooltip(for item:HistoryItem)->String{
		let timestamp=AppDelegate.historyDateFormatter.string(from: item.date)
		guard let payload=item.payload, !item.kind.isFile else{
			return "\(item.deviceName) · \(timestamp)"
		}
		return "\(payload)\n\n\(item.deviceName) · \(timestamp)"
	}

	private func historySymbol(for kind:HistoryKind)->String{
		switch kind{
		case .receivedText, .sentText: return "doc.on.clipboard"
		case .receivedLink, .sentLink: return "link"
		case .receivedFile, .sentFile: return "doc"
		}
	}

	// MARK: - Small helpers

	private var unknownDeviceName:String{
		NSLocalizedString("UnknownDevice", value: "Unknown device", comment: "")
	}

	private func deviceName(forID deviceID:String)->String{
		NearbyConnectionManager.shared.deviceName(forID: deviceID) ?? unknownDeviceName
	}

	private func textPreview(_ text:String)->String{
		let flattened=text.replacingOccurrences(of: "\n", with: " ")
		return flattened.count>140 ? String(flattened.prefix(140))+"…" : flattened
	}

	private func linkSummary(_ text:String)->String{
		guard let url=URL(string: text), let host=url.host else{
			return textPreview(text)
		}
		return host
	}

	private static let historyDateFormatter:DateFormatter={
		let formatter=DateFormatter()
		formatter.dateStyle = .short
		formatter.timeStyle = .short
		return formatter
	}()

	// MARK: - Notifications

	func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
		completionHandler([.banner, .sound])
	}

	func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
		let userInfo=response.notification.request.content.userInfo
		if let transferID=userInfo["transferID"] as? String{
			let action=response.actionIdentifier
			if action=="ACCEPT_ALWAYS"{
				if let deviceName=userInfo["deviceName"] as? String, !deviceName.isEmpty{
					FavouritesStore.shared.add(deviceName)
				}
				NearbyConnectionManager.shared.submitUserConsent(transferID: transferID, accept: true)
			}else{
				NearbyConnectionManager.shared.submitUserConsent(transferID: transferID, accept: action=="ACCEPT")
				if action != "ACCEPT"{
					activeIncomingTransfers.removeValue(forKey: transferID)
				}
			}
		}
		completionHandler()
	}

	private func postInfoNotification(title:String, body:String){
		let content=UNMutableNotificationContent()
		content.title=title
		content.body=body
		content.categoryIdentifier="INFO"
		UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
	}

	private func postErrorNotification(_ message:String, title:String?=nil){
		let content=UNMutableNotificationContent()
		content.title=title ?? NSLocalizedString("Error.Title", value: "QuickShare", comment: "")
		content.body=message
		content.categoryIdentifier="INFO"
		UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
	}

	private func errorMessage(for error:Error)->String{
		if let ne=(error as? NearbyError){
			switch ne{
			case .inputOutput:
				return NSLocalizedString("Error.IO", value: "Disk I/O error", comment: "")
			case .protocolError, .requiredFieldMissing:
				return NSLocalizedString("Error.Protocol", value: "Communication error", comment: "")
			case .ukey2:
				return NSLocalizedString("Error.Crypto", value: "Encryption error", comment: "")
			case .canceled(let reason):
				switch reason{
				case .userRejected: return NSLocalizedString("TransferDeclined", value: "Declined", comment: "")
				case .userCanceled: return NSLocalizedString("TransferCanceled", value: "Canceled", comment: "")
				case .notEnoughSpace: return NSLocalizedString("NotEnoughSpace", value: "Not enough disk space", comment: "")
				case .unsupportedType: return NSLocalizedString("UnsupportedType", value: "Attachment type not supported", comment: "")
				case .timedOut: return NSLocalizedString("TransferTimedOut", value: "Timed out", comment: "")
				}
			}
		}
		return error.localizedDescription
	}

	private func showAlert(title:String, message:String){
		DispatchQueue.main.async {
			let alert=NSAlert()
			alert.messageText=title
			alert.informativeText=message
			alert.addButton(withTitle:"OK")
			alert.runModal()
		}
	}

	private func showNotificationsDeniedAlert(){
		let alert=NSAlert()
		alert.alertStyle = .critical
		alert.messageText=NSLocalizedString("NotificationsDenied.Title", value: "Notification Permission Required", comment: "")
		alert.informativeText=NSLocalizedString("NotificationsDenied.Message", value: "QuickShare needs to display notifications so you can accept incoming transfers. Please allow notifications in System Settings.", comment: "")
		alert.addButton(withTitle: NSLocalizedString("NotificationsDenied.OpenSettings", value: "Open settings", comment: ""))
		alert.addButton(withTitle: NSLocalizedString("Quit", value: "Quit QuickShare", comment: ""))
		let result=alert.runModal()
		if result==NSApplication.ModalResponse.alertFirstButtonReturn{
			NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
		}else if result==NSApplication.ModalResponse.alertSecondButtonReturn{
			NSApplication.shared.terminate(nil)
		}
	}
}

struct TransferInfo{
	let device:RemoteDeviceInfo
	let transfer:TransferMetadata
}

/// Details of an outgoing transfer, remembered until the matching completion
/// event arrives so a history entry can be recorded with the right metadata.
struct PendingOutgoing{
	let kind:HistoryKind
	let title:String
	let payload:String?
	let deviceName:String
}
