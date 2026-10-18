//
//  TransferProgress.swift
//  QuickShare
//
//  Live transfer state for the menu bar dropdown: one card per transfer, with a
//  line per file inside it. The transfer's overall progress sweeps behind the
//  card, each file gets its own thin bar.
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

/// One line in a transfer card: a file, or a summary standing in for the files
/// a long transfer has no room to list.
struct TransferFileRow{
	let name:String
	let fraction:Double
	let isCurrent:Bool
	let isComplete:Bool
	/// The size of the file, or of the group a summary covers.
	let sizeText:String
}

/// Everything a transfer card needs to draw itself. The controller builds these
/// so the view stays free of rate maths.
struct TransferDisplay{
	let id:String
	/// "Sending to Pixel 8 Pro"
	let heading:String
	/// "IMG_1234.jpg", or "IMG_1234.jpg (2 of 5)". Used when there is no file
	/// list to show yet, before the sender's file details have arrived.
	let detail:String
	let fraction:Double
	let percent:Int
	let total:Int64
	/// "523 Mbps", once there is a meaningful rate.
	let rate:String?
	/// "12 s left"
	let timeLeft:String?
	/// Every file in the transfer, in the order it will be sent.
	let files:[TransferFileRow]

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

// MARK: - Menu icons

/// Menu row icons, in one place so every row in the panel behaves the same way.
enum MenuIcon{
	/// A template symbol, so the menu tints it to match the row.
	static func symbol(_ name:String)->NSImage?{
		let image=NSImage(systemSymbolName: name, accessibilityDescription: nil)
		image?.isTemplate=true
		return image
	}

	/// Puts an icon on a menu item.
	static func apply(_ item:NSMenuItem, _ symbolName:String){
		item.image=symbol(symbolName)
		// From macOS 27 AppKit decides for itself whether item images are worth
		// showing, and usually decides they are not. Every actionable row in
		// this menu is built around its icon, so ask for it to be shown.
		if #available(macOS 27.0, *){
			item.preferredImageVisibility = .visible
		}
	}
}

// MARK: - Menu metrics

/// The measurements that let the panel's custom rows sit in the menu as if the
/// menu had drawn them.
///
/// The dropdown mixes stock items with custom views (the header, the transfer
/// cards). A stock item puts its title a little way in from the left of its row;
/// a card's text has to start at the same place or it reads as misaligned. That
/// offset is not a documented constant - it depends on the menu style and on
/// whether the rows carry icons - so measure it on the running system rather
/// than hardcoding a number that would quietly drift.
enum MenuMetrics{
	/// The width the panel is worth having: enough for the longest row plus its
	/// icon, and enough for a transfer card to breathe.
	static let panelWidth:CGFloat=320

	/// Where a title starts in a row that has an icon, which is what the card
	/// text and the header line up with.
	///
	/// This is not a documented constant. A menu reserves one column for item
	/// images, as wide as the widest icon in that menu, and pads either side of
	/// the title; both the column and the padding vary with the menu style and
	/// with the symbols used. So rather than hardcode a number that would drift,
	/// measure it on the running system — from the icons the panel's own rows
	/// carry, which `measure(in:)` collects once the menu has been built.
	static var textInset:CGFloat{
		measuredInset ?? textInset(forImages: [MenuIcon.symbol("eye")].compactMap {$0})
	}

	/// Measures the column from a menu's own items. Call once the rows and their
	/// icons are in place.
	static func measure(in menu:NSMenu){
		measuredInset=textInset(forImages: menu.items.compactMap {$0.image})
	}

	private static var measuredInset:CGFloat?

	/// The title column for a set of icons: a menu sets aside room for its
	/// widest icon, and a row without one gets no column at all.
	private static func textInset(forImages images:[NSImage])->CGFloat{
		let column=min(images.map(iconColumn(for:)).max() ?? 0, maxColumn)
		return column+padding()
	}

	/// A menu draws item images in a box of its own choosing — measured at 16
	/// points here, whatever size the symbol asks for — with a small gap after
	/// it. A symbol wider than the box, like the eye, is drawn scaled down
	/// inside it and does not push the titles any further in, so the column the
	/// icons add tops out here.
	private static let maxColumn:CGFloat=20

	/// The space a menu leaves on either side of a title, when the row has no
	/// icon.
	private static func padding()->CGFloat{
		let title="Mg"
		let textWidth=ceil((title as NSString).size(withAttributes: [.font: NSFont.menuFont(ofSize: 0)]).width)
		let plain=menuWidth(title: title, image: nil)
		// Whatever is left of the row once the title is in it, halved.
		return max(0, (plain-textWidth)/2)
	}

	/// How much room an icon takes up in the title column: the width it adds to
	/// a one-item menu.
	private static func iconColumn(for image:NSImage)->CGFloat{
		let title="Mg"
		return max(0, menuWidth(title: title, image: image)-menuWidth(title: title, image: nil))
	}

	private static func menuWidth(title:String, image:NSImage?)->CGFloat{
		let menu=NSMenu()
		let item=NSMenuItem(title: title, action: nil, keyEquivalent: "")
		if let image=image{
			item.image=image
			// Measure the menu as the panel asks it to be drawn, icons included.
			if #available(macOS 27.0, *){
				item.preferredImageVisibility = .visible
			}
		}
		menu.addItem(item)
		menu.update()
		return menu.size.width
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

// MARK: - Drawing helpers

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

// MARK: - File row

/// One file in a transfer: its name, its size, and a thin bar for its own
/// progress. The card's fill is the transfer as a whole; this is the detail
/// underneath it.
final class FileRowView:LayerBackgroundView{
	private let nameLabel=NSTextField(labelWithString:"")
	private let sizeLabel=NSTextField(labelWithString:"")
	private let barTrack=LayerBackgroundView()
	private let barFill=LayerBackgroundView()

	static let height:CGFloat=19
	private static let barHeight:CGFloat=2.5

	private var fraction:Double=0

	override var isFlipped:Bool{
		return true
	}

	init(){
		super.init(frame: NSRect(x: 0, y: 0, width: 100, height: FileRowView.height))
		fillColor = .clear

		nameLabel.font = .systemFont(ofSize: 11)
		nameLabel.lineBreakMode = .byTruncatingMiddle

		sizeLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
		sizeLabel.textColor = .tertiaryLabelColor
		sizeLabel.alignment = .right

		barTrack.fillColor = NSColor.labelColor.withAlphaComponent(0.10)
		barTrack.cornerRadius = FileRowView.barHeight/2
		barFill.fillColor = NSColor.labelColor.withAlphaComponent(0.32)
		barFill.cornerRadius = FileRowView.barHeight/2

		for view in [nameLabel, sizeLabel, barTrack, barFill] as [NSView]{
			addSubview(view)
		}
	}

	required init?(coder:NSCoder){
		fatalError("not supported")
	}

	func update(_ row:TransferFileRow){
		nameLabel.stringValue=row.name
		// The file being written is the live one, so it keeps full contrast;
		// finished files recede, and ones still waiting are dimmest of all.
		nameLabel.textColor = row.isCurrent ? .labelColor : (row.isComplete ? .secondaryLabelColor : .tertiaryLabelColor)
		sizeLabel.stringValue=row.sizeText
		fraction=row.fraction
		needsLayout=true
	}

	override func layout(){
		let width=bounds.width
		let sizeWidth=min(width*0.35, ceil(sizeLabel.intrinsicContentSize.width))
		let nameWidth=max(0, width-sizeWidth-8)
		nameLabel.frame=NSRect(x: 0, y: 0, width: nameWidth, height: 14)
		sizeLabel.frame=NSRect(x: nameWidth+8, y: 2, width: sizeWidth, height: 12)
		barTrack.frame=NSRect(x: 0, y: FileRowView.height-FileRowView.barHeight, width: width, height: FileRowView.barHeight)
		barFill.frame=NSRect(x: 0, y: barTrack.frame.minY,
		                     width: (width*CGFloat(min(1, max(0, fraction)))).rounded(),
		                     height: FileRowView.barHeight)
		barFill.isHidden=fraction<=0
	}
}

// MARK: - Card

/// One transfer: the percentage and rate on top, then a line per file.
final class TransferCard:LayerBackgroundView{

	/// How far the card sits in from the edges of its menu row, so it does not
	/// touch the edges of the menu itself.
	static let boxInset:CGFloat=6
	/// Files listed individually before the rest are summarised.
	static let maxFileRows=6

	/// Where the card's text starts, from the card's own left edge: the row's
	/// title column, less the box inset the card sits behind, so the card's
	/// text lines up with the titles of the rows around it.
	private static var contentInset:CGFloat{
		max(0, MenuMetrics.textInset-boxInset)
	}
	private static let topInset:CGFloat=5
	private static let headerTop:CGFloat=13
	private static let percentHeight:CGFloat=17
	private static let detailHeight:CGFloat=14
	private static let rateHeight:CGFloat=15
	private static let closeSize:CGFloat=20

	private let progressFill=LayerBackgroundView()
	private let percentLabel=NSTextField(labelWithString:"")
	private let detailLabel=NSTextField(labelWithString:"")
	private let rateIcon=NSImageView()
	private let rateLabel=NSTextField(labelWithString:"")
	private let closeButton=NSButton()
	private var fileRows:[FileRowView]=[]

	private var showsDetail=false
	private var fraction:Double=0

	private var onClose:(()->Void)?

	override var isFlipped:Bool{
		return true
	}

	/// How tall the card for a transfer comes out: a header, then one line per
	/// file.
	static func height(for display:TransferDisplay)->CGFloat{
		var height=headerTop+percentHeight+3+rateHeight
		if showsDetail(display){
			height+=2+detailHeight
		}
		if !display.files.isEmpty{
			height+=7+CGFloat(display.files.count)*FileRowView.height
		}
		return height+11
	}

	/// The single "name (2 of 5)" line is only worth showing when there is no
	/// file list yet; once the files are listed it would just repeat them.
	private static func showsDetail(_ display:TransferDisplay)->Bool{
		display.files.isEmpty && !display.detail.isEmpty
	}

	/// Wraps a card in a menu item. The row spans the whole menu and the card
	/// sits inside it, so its text starts where the menu's own titles do.
	static func menuItem(for display:TransferDisplay, onClose:@escaping ()->Void)->(item:NSMenuItem, card:TransferCard){
		let card=TransferCard(onClose: onClose)
		card.frame=NSRect(x: boxInset, y: topInset,
		                  width: MenuMetrics.panelWidth-2*boxInset,
		                  height: height(for: display))

		let container=NSView(frame: NSRect(x: 0, y: 0, width: MenuMetrics.panelWidth, height: card.frame.height+2*topInset))
		// Menu item views are only stretched to the menu's full width if they
		// say they want to be.
		container.autoresizingMask=[.width]
		card.autoresizingMask=[.width]
		container.addSubview(card)
		card.update(display)

		let item=NSMenuItem()
		item.view=container
		return (item, card)
	}

	init(onClose:@escaping ()->Void){
		self.onClose=onClose
		super.init(frame: NSRect(x: 0, y: 0, width: MenuMetrics.panelWidth-2*TransferCard.boxInset, height: 78))
		cornerRadius=12
		fillColor = NSColor.labelColor.withAlphaComponent(0.06)

		progressFill.fillColor = NSColor.labelColor.withAlphaComponent(0.16)

		percentLabel.font = .systemFont(ofSize: 13, weight: .semibold)
		percentLabel.lineBreakMode = .byTruncatingTail

		detailLabel.font = .systemFont(ofSize: 11)
		detailLabel.textColor = .secondaryLabelColor
		detailLabel.lineBreakMode = .byTruncatingMiddle

		rateIcon.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
		rateIcon.contentTintColor = .secondaryLabelColor
		rateIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)

		rateLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
		rateLabel.textColor = .secondaryLabelColor
		rateLabel.lineBreakMode = .byTruncatingTail

		closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: NSLocalizedString("Transfer.Dismiss", value: "Dismiss", comment: ""))
		closeButton.isBordered=false
		closeButton.bezelStyle = .circular
		closeButton.contentTintColor = .tertiaryLabelColor
		closeButton.imagePosition = .imageOnly
		closeButton.target=self
		closeButton.action = #selector(closeTapped(_:))

		for view in [progressFill, percentLabel, detailLabel, rateIcon, rateLabel, closeButton] as [NSView]{
			addSubview(view)
		}
	}

	required init?(coder:NSCoder){
		fatalError("not supported")
	}

	@objc private func closeTapped(_ sender:Any?){
		onClose?()
	}

	func update(_ display:TransferDisplay){
		if fileRows.count != display.files.count{
			for row in fileRows{
				row.removeFromSuperview()
			}
			fileRows=display.files.map{ _ in FileRowView() }
			for row in fileRows{
				addSubview(row)
			}
			frame.size.height=TransferCard.height(for: display)
		}
		percentLabel.stringValue=display.percentText
		showsDetail=TransferCard.showsDetail(display)
		detailLabel.stringValue=display.detail
		detailLabel.isHidden = !showsDetail
		if let rateText=display.rateText{
			rateIcon.isHidden=false
			rateLabel.isHidden=false
			rateLabel.stringValue=rateText
		}else{
			rateIcon.isHidden=true
			rateLabel.isHidden=true
		}
		for (row, file) in zip(fileRows, display.files){
			row.update(file)
		}
		fraction=display.fraction
		needsLayout=true
	}

	override func layout(){
		let width=bounds.width
		let inset=TransferCard.contentInset
		let textWidth=max(0, width-inset-TransferCard.closeSize-10-inset)

		var y=TransferCard.headerTop
		percentLabel.frame=NSRect(x: inset, y: y, width: textWidth, height: TransferCard.percentHeight)
		// The × sits on the headline rather than in the middle of the card:
		// cards with several files get tall, and a centred button drifts away
		// from everything it refers to.
		closeButton.frame=NSRect(x: width-inset-TransferCard.closeSize,
		                         y: y+(TransferCard.percentHeight-TransferCard.closeSize)/2,
		                         width: TransferCard.closeSize, height: TransferCard.closeSize)
		y+=TransferCard.percentHeight

		if showsDetail{
			y+=2
			detailLabel.frame=NSRect(x: inset, y: y, width: textWidth, height: TransferCard.detailHeight)
			y+=TransferCard.detailHeight
		}

		y+=3
		rateIcon.frame=NSRect(x: inset, y: y+2, width: 12, height: 12)
		rateLabel.frame=NSRect(x: inset+16, y: y, width: max(0, textWidth-16), height: TransferCard.rateHeight)
		y+=TransferCard.rateHeight

		if !fileRows.isEmpty{
			y+=7
			for row in fileRows{
				row.frame=NSRect(x: inset, y: y, width: max(0, width-2*inset), height: FileRowView.height)
				y+=FileRowView.height
			}
		}

		let filled=CGFloat(min(1, max(0, fraction)))
		progressFill.frame=NSRect(x: 0, y: 0, width: (width*filled).rounded(), height: bounds.height)
	}
}

// MARK: - Controller

/// Tracks every transfer in flight and tells the app when to redraw.
final class TransferProgressController{

	static let shared=TransferProgressController()

	/// Mirrors the rate into the menu bar title, or `nil` when nothing is
	/// transferring.
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

	/// The rate alone — "49.6 Mbps" — because that is what you glance at the
	/// menu bar for while a transfer runs. Before the first sample lands there
	/// is no rate yet, so it falls back to the percentage rather than sitting
	/// blank.
	private func statusText(for transfer:ActiveTransfer)->String{
		transfer.rateText ?? "\(transfer.percent)%"
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
	/// Every file in the transfer, in the order it will be sent.
	var files:[TransferProgress.FileProgress]
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
		self.files=progress.files
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
		files=progress.files
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
		                timeLeft: timeLeftText,
		                files: fileRows())
	}

	/// The file lines, with the ones that would not fit folded into a summary
	/// at whichever end they fall off.
	private func fileRows()->[TransferFileRow]{
		guard !files.isEmpty else {return []}
		let current=files.firstIndex(where: {!$0.isComplete})

		func row(_ file:TransferProgress.FileProgress, index:Int)->TransferFileRow{
			TransferFileRow(name: file.name,
			                fraction: file.fraction,
			                isCurrent: index==current,
			                isComplete: file.isComplete,
			                sizeText: byteString(file.totalBytes))
		}

		guard files.count>TransferCard.maxFileRows else {
			return files.enumerated().map { row($0.element, index: $0.offset) }
		}

		// Keep the file being worked on in view, near its neighbours.
		let start=max(0, min((current ?? 0)-2, files.count-TransferCard.maxFileRows))
		let end=min(files.count, start+TransferCard.maxFileRows)
		var rows:[TransferFileRow]=[]
		if start>0{
			// Everything before the window: files go one at a time in order, so
			// these are done rather than merely hidden.
			rows.append(summary(of: Array(files[0..<start]),
			                    label: NSLocalizedString("Transfer.FilesDone", value: "%d files done", comment: "")))
		}
		rows.append(contentsOf: (start..<end).map { row(files[$0], index: $0) })
		if end<files.count{
			rows.append(summary(of: Array(files[end...]),
			                    label: NSLocalizedString("Transfer.FilesMore", value: "%d more files", comment: "")))
		}
		return rows
	}

	private func summary(of group:[TransferProgress.FileProgress], label:String)->TransferFileRow{
		let transferred=group.reduce(Int64(0)) {$0+$1.transferredBytes}
		let total=group.reduce(Int64(0)) {$0+$1.totalBytes}
		return TransferFileRow(name: String(format: label, group.count),
		                       fraction: total>0 ? Double(transferred)/Double(total) : 0,
		                       isCurrent: false,
		                       isComplete: group.allSatisfy {$0.isComplete},
		                       sizeText: byteString(total))
	}
}
