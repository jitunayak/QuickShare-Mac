//
//  History.swift
//  QuickShare
//
//  A rolling list of the most recent transfers (received and sent), capped at
//  ten entries and persisted to UserDefaults so it survives relaunches.
//

import Foundation
import Combine

enum HistoryKind: String, Codable {
	case receivedText
	case receivedLink
	case receivedFile
	case sentText
	case sentLink
	case sentFile

	var outgoing: Bool {
		switch self {
		case .sentText, .sentLink, .sentFile: return true
		default: return false
		}
	}

	var isText: Bool {
		switch self {
		case .receivedText, .sentText: return true
		default: return false
		}
	}

	var isLink: Bool {
		switch self {
		case .receivedLink, .sentLink: return true
		default: return false
		}
	}

	var isFile: Bool {
		switch self {
		case .receivedFile, .sentFile: return true
		default: return false
		}
	}
}

struct HistoryItem: Codable, Identifiable {
	let id: UUID
	let kind: HistoryKind
	/// Short, user-facing summary: a text preview, a link host or a file name.
	let title: String
	/// Full text/link, or the file path(s) (newline separated) needed to act again.
	let payload: String?
	let deviceName: String
	let date: Date
}

final class HistoryStore: ObservableObject {
	static let shared = HistoryStore()
	static let maxItems = 10

	/// Most recent first.
	@Published private(set) var items: [HistoryItem] = []

	private let defaults = UserDefaults.standard
	private let storageKey = "transferHistory"

	private init() {
		load()
	}

	/// Inserts an item, trimming the list back down to `maxItems`.
	func add(_ item: HistoryItem) {
		items.insert(item, at: 0)
		if items.count > HistoryStore.maxItems {
			items.removeLast(items.count - HistoryStore.maxItems)
		}
		save()
	}

	func record(kind: HistoryKind, title: String, payload: String?, deviceName: String, date: Date = Date()) {
		add(HistoryItem(id: UUID(), kind: kind, title: title, payload: payload, deviceName: deviceName, date: date))
	}

	func clear() {
		items.removeAll()
		save()
	}

	private func load() {
		guard let data = defaults.data(forKey: storageKey),
		      let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) else { return }
		items = Array(decoded.prefix(HistoryStore.maxItems))
	}

	private func save() {
		guard let data = try? JSONEncoder().encode(items) else { return }
		defaults.set(data, forKey: storageKey)
	}
}
