// swift-tools-version:5.9
//
//  Package.swift
//  QuickShareKit
//
//  The QuickShare app is built with the QuickShare.xcodeproj project, but the
//  protocol core is plain Swift and can also be built and tested standalone:
//
//      swift build
//
import PackageDescription

let package = Package(
	name: "QuickShareKit",
	platforms: [
		.macOS(.v12)
	],
	products: [
		.library(name: "QuickShareKit", targets: ["QuickShareKit"])
	],
	dependencies: [
		.package(url: "https://github.com/apple/swift-protobuf.git", from: "1.21.0"),
		.package(url: "https://github.com/leif-ibsen/SwiftECC", from: "3.0.0"),
	],
	targets: [
		.target(
			name: "QuickShareKit",
			dependencies: [
				.product(name: "SwiftProtobuf", package: "swift-protobuf"),
				.product(name: "SwiftECC", package: "SwiftECC"),
			],
			path: "QuickShareKit",
			exclude: [
				"ProtobufSource",
				"GenerateProtobuf.sh",
			]
		)
	]
)
