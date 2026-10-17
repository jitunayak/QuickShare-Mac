//
//  Favourites.swift
//  QuickShare
//
//  Devices that are allowed to send to this Mac without any prompt. An incoming
//  transfer from a favourite device is accepted silently — no notification.
//
//  The protocol does not expose a stable per-device identifier on an incoming
//  connection (the endpoint info only carries a display name and a random
//  session value), so favourites are matched on the device name. Treat this as
//  a convenience, not a security boundary.
//

import Foundation
import Combine

final class FavouritesStore: ObservableObject {
	static let shared=FavouritesStore()

	/// Device names, in the order they were added.
	@Published private(set) var names:[String]=[]

	/// Draft text for the "add device" field in Preferences. Kept on the store
	/// rather than in `@State` because `@State` is a macro and needs the full
	/// Xcode toolchain (unavailable in a Command-Line-Tools-only build).
	@Published var draftName:String=""

	private let defaults=UserDefaults.standard
	private let storageKey="favouriteDevices"

	private init(){
		names=defaults.stringArray(forKey: storageKey) ?? []
	}

	func isFavourite(_ name:String?) -> Bool {
		guard let name=name, !name.isEmpty else {return false}
		return names.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
	}

	/// Adds a device name. Returns `false` if it was empty or already present.
	@discardableResult
	func add(_ name:String) -> Bool {
		let trimmed=name.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty, !isFavourite(trimmed) else {return false}
		names.append(trimmed)
		save()
		return true
	}

	func remove(_ name:String){
		names.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
		save()
	}

	func removeAll(){
		names.removeAll()
		save()
	}

	private func save(){
		defaults.set(names, forKey: storageKey)
	}
}
