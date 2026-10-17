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

@main
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSMenuDelegate, MainAppDelegate, ShareExtensionDelegate {
	private var statusItem:NSStatusItem?
	private var clipboardMenu:NSMenu?
	private var filesMenu:NSMenu?
	private var activeIncomingTransfers:[String:TransferInfo]=[:]
	private var lastTextReceivedFrom:RemoteDeviceInfo?

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
			UNNotificationAction(identifier: "DECLINE", title: NSLocalizedString("Decline", comment: ""))
		], intentIdentifiers: [])
		let infoCategory=UNNotificationCategory(identifier: "INFO", actions: [], intentIdentifiers: [])
		nc.setNotificationCategories([incomingTransfersCategory, infoCategory])

		NearbyConnectionManager.shared.mainAppDelegate=self
		NearbyConnectionManager.shared.onDevicesChanged={ [weak self] in
			self?.rebuildDeviceMenus()
		}
		NearbyConnectionManager.shared.becomeVisible()
	}

	func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
		statusItem?.isVisible=true
		return true
	}

	func applicationWillTerminate(_ aNotification: Notification) {
		UNUserNotificationCenter.current().removeAllDeliveredNotifications()
	}

	func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
		return true
	}

	// MARK: - Menu bar

	private func buildStatusMenu(){
		let menu=NSMenu()
		menu.delegate=self

		let visible=NSMenuItem(title: NSLocalizedString("VisibleToEveryone", value: "Visible to everyone on this network", comment: ""), action: nil, keyEquivalent: "")
		visible.isEnabled=false
		menu.addItem(visible)

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

		menu.addItem(NSMenuItem.separator())
		let prefsItem=NSMenuItem(title: NSLocalizedString("Preferences", value: "Preferences…", comment: ""), action: #selector(openPreferences(_:)), keyEquivalent: ",")
		prefsItem.target=self
		menu.addItem(prefsItem)
		menu.addItem(NSMenuItem.separator())
		menu.addItem(NSMenuItem(title: NSLocalizedString("Quit", value: "Quit QuickShare", comment: ""), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

		statusItem=NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
		statusItem?.button?.image=NSImage(named: "MenuBarIcon")
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
		NearbyConnectionManager.shared.sendText(text, isURL: isURL, toDeviceID: deviceID){ [weak self] result in
			switch result{
			case .success:
				self?.postInfoNotification(title: NSLocalizedString("ClipboardSent.Title", value: "Clipboard sent", comment: ""), body: NSLocalizedString("ClipboardSent.Body", value: "The clipboard was shared successfully.", comment: ""))
			case .failure(let error):
				self?.postErrorNotification(error.localizedDescription)
			}
		}
	}

	@objc private func sendFilesToDevice(_ sender:NSMenuItem){
		guard let deviceID=sender.representedObject as? String else {return}
		let panel=NSOpenPanel()
		panel.canChooseFiles=true
		panel.canChooseDirectories=false
		panel.allowsMultipleSelection=true
		panel.prompt=NSLocalizedString("Send", comment: "")
		NSApp.activate(ignoringOtherApps: true)
		panel.begin { response in
			guard response == .OK, !panel.urls.isEmpty else {return}
			NearbyConnectionManager.shared.startOutgoingTransfer(deviceID: deviceID, delegate: self, urls: panel.urls)
		}
	}

	@objc private func openPreferences(_ sender:Any?){
		PreferencesWindowController.shared.show()
	}

	// MARK: - MainAppDelegate (receiving)

	func obtainUserConsent(for transfer: TransferMetadata, from device: RemoteDeviceInfo) {
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
		content.userInfo=["transferID": transfer.id]
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
		if isURL{
			postInfoNotification(title: NSLocalizedString("LinkReceived.Title", value: "Link opened", comment: ""), body: text)
		}else{
			let preview=text.count>140 ? String(text.prefix(140))+"…" : text
			postInfoNotification(title: NSLocalizedString("TextReceived.Title", value: "Text copied to clipboard", comment: ""), body: preview)
		}
	}

	func incomingFile(at url: URL, from device: RemoteDeviceInfo?) {
		postInfoNotification(title: NSLocalizedString("FileReceived.Title", value: "File received", comment: ""), body: url.lastPathComponent)
	}

	// MARK: - ShareExtensionDelegate (sending initiated from this app)

	func addDevice(device: RemoteDeviceInfo) { rebuildDeviceMenus() }
	func removeDevice(id: String) { rebuildDeviceMenus() }
	func startTransferWithQrCode(device: RemoteDeviceInfo) {}
	func connectionWasEstablished(pinCode: String) {}
	func transferAccepted() {}
	func transferProgress(progress: Double) {}
	func transferFinished() {
		postInfoNotification(title: NSLocalizedString("Sent.Title", value: "Sent", comment: ""), body: NSLocalizedString("Sent.Body", value: "The transfer completed successfully.", comment: ""))
	}
	func connectionFailed(with error: Error) {
		postErrorNotification(errorMessage(for: error))
	}

	// MARK: - Notifications

	func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
		completionHandler([.banner, .sound])
	}

	func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
		if let transferID=response.notification.request.content.userInfo["transferID"] as? String{
			NearbyConnectionManager.shared.submitUserConsent(transferID: transferID, accept: response.actionIdentifier=="ACCEPT")
			if response.actionIdentifier != "ACCEPT"{
				activeIncomingTransfers.removeValue(forKey: transferID)
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
