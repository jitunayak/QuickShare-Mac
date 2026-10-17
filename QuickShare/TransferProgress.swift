//
//  TransferProgress.swift
//  QuickShare
//
//  Live transfer state for the menu bar dropdown: one card per transfer, each
//  showing its progress as a background fill, the bytes moved, the rate and a
//  close button.
//

import Cocoa
import QuickShareKit

enum TransferDirection{
	case sending, receiving

	/// "Sending to %@" / "Receiving from %@"
	var headline:String{
		switch self{
		case .sending:
			return NSLocalizedString("Transfer.Sending", value: "Sending to %@", comment: "")
		case .receiving:
			return NSLocalizedString("Transfer.Receiving", value: "Receiving from %@", comment: "")
		}
	}
}

/// Everything a transfer card needs to draw itself. The controller builds these
/// so the view stays free of rate maths.
struct TransferDisplay{
	let id:String
	/// "Sending to Pixel 8 Pro"
	let heading:String
	/// "IMG_1234.jpg", or "IMG_1234.jpg (2 of 5)"
	let detail:String
	let fraction:Double
	let percent:Int
	let total:Int64
	/// "523 Mbps", once there is a meaningful rate.
	let rate:String?
	/// "12 s left"
	let timeLeft:String?

	/// "77% of 266.1 MB"
	var percentText:String{
		String(format: NSLocalizedString("Transfer.PercentOf", value: "%d%% of %@", comment: ""), percent, byteString(total))
	}

	var rateText:String?{
		guard let rate=rate else {return nil}
		guard let timeLeft=timeLeft else {return rate}
		return "\(rate) · \(timeLeft)"
	}
}

/// One transfer that is currently in flight.
private struct ActiveTransfer{
	let id:String
	var deviceName:String
	let direction:TransferDirection
	var transferred:Int64
	var total:Int64
	var currentFileName:String?
	var filesTransferred:Int
	var filesTotal:Int
	var speed:Double=0
	private var lastBytes:Int64
	private var lastSampleAt=Date()

	init(id:String, deviceName:String, direction:TransferDirection, progress:TransferProgress){
		self.id=id
		self.deviceName=deviceName
		self.direction=direction
		self.transferred=progress.transferredBytes
		self.total=progress.totalBytes
		self.currentFileName=progress.currentFileName
		self.filesTransferred=progress.filesTransferred
		self.filesTotal=progress.filesTotal
		self.lastBytes=progress.transferredBytes
	}

	/// Folds a new byte count in.
	///
	/// Chunks arrive in bursts, so the raw delta between two samples makes the
	/// rate jump around; an exponential average keeps it readable.
	mutating func sample(_ progress:TransferProgress){
		let now=Date()
		let elapsed=now.timeIntervalSince(lastSampleAt)
		transferred=progress.transferredBytes
		total=progress.totalBytes
		currentFileName=progress.currentFileName
		filesTransferred=progress.filesTransferred
		filesTotal=progress.filesTotal
		guard elapsed>=0.25, progress.transferredBytes>=lastBytes else {return}
		let instant=Double(progress.transferredBytes-lastBytes)/elapsed
		speed=speed<=0 ? instant : speed*0.7+instant*0.3
		lastBytes=progress.transferredBytes
		lastSampleAt=now
	}

	/// Called from the refresh timer so a stalled transfer stops claiming a
	/// rate it is no longer achieving.
	mutating func decaySpeed(ifIdleFor interval:TimeInterval){
		guard Date().timeIntervalSince(lastSampleAt)>interval else {return}
		speed*=0.5
		if speed<1024{
			speed=0
		}
		lastSampleAt=Date()
	}

	var fraction:Double{
		guard total>0 else {return 0}
		return min(1, max(0, Double(transferred)/Double(total)))
	}

	var percent:Int{
		Int((fraction*100).rounded())
	}

	/// "IMG_1234.jpg", or "IMG_1234.jpg (2 of 5)" for a multi-file share.
	var detail:String{
		guard let name=currentFileName, !name.isEmpty else {
			guard filesTotal>1 else {return ""}
			return String(format: NSLocalizedString("History.NFiles", value: "%d files", comment: ""), filesTotal)
		}
		guard filesTotal>1 else {return name}
		return String(format: NSLocalizedString("Transfer.FileNofM", value: "%@ (%d of %d)", comment: ""),
		              name, min(filesTransferred+1, filesTotal), filesTotal)
	}

	/// "13.8 MB/s" worth of data, but quoted the way network transfers are.
	var rateText:String?{
		guard speed>1024 else {return nil}
		let mbps=speed*8/1_000_000
		guard mbps>=100 else {
			return String(format: NSLocalizedString("Transfer.Mbps", value: "%.1f Mbps", comment: ""), mbps)
		}
		return String(format: NSLocalizedString("Transfer.MbpsWhole", value: "%.0f Mbps", comment: ""), mbps)
	}

	var timeLeftText:String?{
		guard speed>1024 else {return nil}
		let seconds=Double(total-transferred)/speed
		guard seconds>0.5 && seconds<3600 else {return nil}
		return String(format: NSLocalizedString("Transfer.TimeLeft", value: "%@ left", comment: ""), timeString(seconds))
	}

	func display()->TransferDisplay{
		TransferDisplay(id: id,
		                heading: String(format: direction.headline, deviceName),
		                detail: detail,
		                fraction: fraction,
		                percent: percent,
		                total: total,
		                rate: rateText,
		                timeLeft: timeLeftText)
	}
}

// MARK: - Formatting

private let byteFormatter:ByteCountFormatter={
	let formatter=ByteCountFormatter()
	formatter.countStyle = .file
	formatter.allowedUnits = [.useKB, .useMB, .useGB]
	return formatter
}()

private func byteString(_ bytes:Int64)->String{
	byteFormatter.string(fromByteCount: max(0, bytes))
}

private func timeString(_ seconds:Double)->String{
	let total=Int(seconds.rounded())
	if total<60{
		return String(format: NSLocalizedString("Transfer.Seconds", value: "%d s", comment: ""), total)
	}
	let minutes=total/60
	if minutes<60{
		return String(format: NSLocalizedString("Transfer.Minutes", value: "%d m %d s", comment: ""), minutes, total%60)
	}
	return String(format: NSLocalizedString("Transfer.Hours", value: "%d h %d m", comment: ""), minutes/60, minutes%60)
}

// MARK: - Card

/// Draws a flat colour and optional corner radius, re-applying both on
/// appearance changes so it follows light and dark mode.
class LayerBackgroundView:NSView{
	var fillColor:NSColor = .clear
	var cornerRadius:CGFloat = 0

	override var wantsUpdateLayer:Bool{
		return true
	}

	override func updateLayer(){
		layer?.backgroundColor=fillColor.cgColor
		layer?.cornerRadius=cornerRadius
		layer?.masksToBounds=cornerRadius>0
	}
}

/// One transfer row: the progress sweeps across the card behind the text.
final class TransferCard:LayerBackgroundView{

	static let width:CGFloat=304
	static let height:CGFloat=78
	/// So the rounded corners are visible inside the menu.
	private static let menuInset:CGFloat=5

	private let progressFill=LayerBackgroundView()
	private let percentLabel=NSTextField(labelWithString:"")
	private let detailLabel=NSTextField(labelWithString:"")
	private let rateIcon=NSImageView()
	private let rateLabel=NSTextField(labelWithString:"")
	private let closeButton=NSButton()

	private var fillWidth:NSLayoutConstraint!

	private var onClose:(()->Void)?

	/// Wraps a card in a menu item.
	static func menuItem(for display:TransferDisplay, onClose:@escaping ()->Void)->(item:NSMenuItem, card:TransferCard){
		let container=NSView(frame: NSRect(x: 0, y: 0, width: width+2*menuInset, height: height+2*menuInset))
		let card=TransferCard(onClose: onClose)
		card.frame=NSRect(x: menuInset, y: menuInset, width: width, height: height)
		container.addSubview(card)
		let item=NSMenuItem()
		item.view=container
		return (item, card)
	}

	init(onClose:@escaping ()->Void){
		self.onClose=onClose
		super.init(frame: NSRect(x: 0, y: 0, width: TransferCard.width, height: TransferCard.height))
		cornerRadius=12
		fillColor = NSColor.labelColor.withAlphaComponent(0.06)

		progressFill.fillColor = NSColor.labelColor.withAlphaComponent(0.16)
		progressFill.translatesAutoresizingMaskIntoConstraints=false

		percentLabel.font = .systemFont(ofSize: 13, weight: .semibold)
		percentLabel.lineBreakMode = .byTruncatingTail
		percentLabel.translatesAutoresizingMaskIntoConstraints=false

		detailLabel.font = .systemFont(ofSize: 11)
		detailLabel.textColor = .secondaryLabelColor
		detailLabel.lineBreakMode = .byTruncatingMiddle
		detailLabel.translatesAutoresizingMaskIntoConstraints=false

		rateIcon.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
		rateIcon.contentTintColor = .secondaryLabelColor
		rateIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
		rateIcon.translatesAutoresizingMaskIntoConstraints=false

		rateLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
		rateLabel.textColor = .secondaryLabelColor
		rateLabel.translatesAutoresizingMaskIntoConstraints=false

		closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: NSLocalizedString("Transfer.Dismiss", value: "Dismiss", comment: ""))
		closeButton.isBordered=false
		closeButton.bezelStyle = .circular
		closeButton.contentTintColor = .tertiaryLabelColor
		closeButton.imagePosition = .imageOnly
		closeButton.target=self
		closeButton.action = #selector(closeTapped(_:))
		closeButton.translatesAutoresizingMaskIntoConstraints=false

		for view in [progressFill, percentLabel, detailLabel, rateIcon, rateLabel, closeButton] as [NSView]{
			addSubview(view)
		}

		fillWidth=progressFill.widthAnchor.constraint(equalToConstant: 0)

		NSLayoutConstraint.activate([
			fillWidth,
			progressFill.leadingAnchor.constraint(equalTo: leadingAnchor),
			progressFill.topAnchor.constraint(equalTo: topAnchor),
			progressFill.bottomAnchor.constraint(equalTo: bottomAnchor),

			percentLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
			percentLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -10),
			percentLabel.topAnchor.constraint(equalTo: topAnchor, constant: 13),

			detailLabel.leadingAnchor.constraint(equalTo: percentLabel.leadingAnchor),
			detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -10),
			detailLabel.topAnchor.constraint(equalTo: percentLabel.bottomAnchor, constant: 2),

			rateIcon.leadingAnchor.constraint(equalTo: percentLabel.leadingAnchor),
			rateIcon.centerYAnchor.constraint(equalTo: rateLabel.centerYAnchor),
			rateIcon.widthAnchor.constraint(equalToConstant: 12),
			rateIcon.heightAnchor.constraint(equalToConstant: 12),

			rateLabel.leadingAnchor.constraint(equalTo: rateIcon.trailingAnchor, constant: 4),
			rateLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -10),
			rateLabel.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 3),

			closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
			closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
			closeButton.widthAnchor.constraint(equalToConstant: 20),
			closeButton.heightAnchor.constraint(equalToConstant: 20),
		])
	}

	required init?(coder:NSCoder){
		fatalError("not supported")
	}

	@objc private func closeTapped(_ sender:Any?){
		onClose?()
	}

	func update(_ display:TransferDisplay){
		percentLabel.stringValue=display.percentText
		detailLabel.stringValue=display.detail
		detailLabel.isHidden=display.detail.isEmpty
		if let rateText=display.rateText{
			rateIcon.isHidden=false
			rateLabel.isHidden=false
			rateLabel.stringValue=rateText
		}else{
			rateIcon.isHidden=true
			rateLabel.isHidden=true
		}
		fillWidth.constant=TransferCard.width*CGFloat(display.fraction)
		setNeedsDisplay(bounds)
	}
}

// MARK: - Controller

/// Tracks every transfer in flight and tells the app when to redraw.
final class TransferProgressController{

	static let shared=TransferProgressController()

	/// Mirrors the headline progress into the menu bar title — percentage and
	/// rate — or `nil` when nothing is transferring.
	var onStatusChanged:((String?)->Void)?
	/// A transfer appeared, finished or was dismissed: the menu items need to
	/// be rebuilt.
	var onTransfersChanged:(()->Void)?
	/// The numbers moved: redraw the existing cards.
	var onProgressChanged:(()->Void)?

	private var active:[String:ActiveTransfer]=[:]
	/// Insertion order, so the menu list is stable.
	private var order:[String]=[]
	/// Transfers the user closed, which stay hidden while they run.
	private var dismissed:Set<String>=[]
	private var reportedStatus:String?=nil

	private init(){}

	/// Live transfers, oldest first. Dismissed ones are filtered out.
	var transfers:[TransferDisplay]{
		order.filter {!dismissed.contains($0)}.compactMap { active[$0]?.display() }
	}

	/// True while something is being tracked, dismissed or not.
	var hasTransfers:Bool{
		!active.isEmpty
	}

	// MARK: - Transfer lifecycle

	/// Creates the transfer on its first report and updates it afterwards.
	func update(id:String, deviceName:String, direction:TransferDirection, progress:TransferProgress){
		let isNew=active[id]==nil
		if isNew{
			active[id]=ActiveTransfer(id: id, deviceName: deviceName, direction: direction, progress: progress)
			order.append(id)
		}else{
			active[id]?.deviceName=deviceName
			active[id]?.sample(progress)
		}
		reportStatus()
		if isNew{
			onTransfersChanged?()
		}else{
			onProgressChanged?()
		}
	}

	/// Drops a transfer — on completion, failure or cancellation.
	func finish(id:String){
		guard active.removeValue(forKey: id) != nil else {return}
		order.removeAll {$0==id}
		dismissed.remove(id)
		reportStatus()
		onTransfersChanged?()
	}

	/// The user closed the card. The transfer itself keeps running; only its
	/// row goes away.
	func dismiss(id:String){
		guard active[id] != nil, !dismissed.contains(id) else {return}
		dismissed.insert(id)
		onTransfersChanged?()
	}

	/// Ages the rates of idle transfers. Called on a timer while the menu is
	/// open so the numbers do not go stale on screen.
	func refreshRates(){
		guard hasTransfers else {return}
		for (id, var transfer) in active{
			transfer.decaySpeed(ifIdleFor: 1.5)
			active[id]=transfer
		}
		reportStatus()
		onProgressChanged?()
	}

	// MARK: - Menu bar title

	private func reportStatus(){
		let status=order.last.flatMap { active[$0] }.map(statusText(for:))
		guard reportedStatus != status else {return}
		reportedStatus=status
		onStatusChanged?(status)
	}

	/// "77% · 523 Mbps", dropping the rate until there is a meaningful one.
	private func statusText(for transfer:ActiveTransfer)->String{
		guard let rate=transfer.rateText else {return "\(transfer.percent)%"}
		return "\(transfer.percent)% · \(rate)"
	}
}
