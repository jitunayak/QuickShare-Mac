//
//  TransferProgress.swift
//  QuickShare
//
//  The floating panel that appears while a file transfer is running: how far
//  along it is, how fast it is going, and roughly how much longer it will take.
//

import Cocoa

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

/// One transfer that is currently in flight.
private struct ActiveTransfer{
	let id:String
	var deviceName:String
	var detail:String
	let direction:TransferDirection
	var transferred:Int64
	var total:Int64
	var speed:Double=0
	private var lastBytes:Int64
	private var lastSampleAt=Date()

	init(id:String, deviceName:String, detail:String, direction:TransferDirection, transferred:Int64, total:Int64){
		self.id=id
		self.deviceName=deviceName
		self.detail=detail
		self.direction=direction
		self.transferred=transferred
		self.total=total
		self.lastBytes=transferred
	}

	/// Folds a new byte count in and returns the smoothed transfer rate.
	///
	/// Chunks arrive in bursts, so the raw delta between two samples makes the
	/// number jump around; an exponential average keeps it readable.
	mutating func sample(transferred:Int64, total:Int64){
		let now=Date()
		let elapsed=now.timeIntervalSince(lastSampleAt)
		self.transferred=transferred
		self.total=total
		guard elapsed>=0.25, transferred>=lastBytes else {return}
		let instant=Double(transferred-lastBytes)/elapsed
		speed=speed<=0 ? instant : speed*0.7+instant*0.3
		lastBytes=transferred
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
}

/// Owns the panel. Every method is expected to be called on the main thread.
final class TransferProgressController{

	static let shared=TransferProgressController()

	/// Mirrors the headline percentage into the menu bar, or `nil` when nothing
	/// is transferring.
	var onPercentChanged:((Int?)->Void)?

	private var transfers:[String:ActiveTransfer]=[:]
	/// The panel follows the transfer that started most recently.
	private var order:[String]=[]
	private var panel:NSPanel?
	private var showWorkItem:DispatchWorkItem?
	private var hideWorkItem:DispatchWorkItem?
	private var refreshTimer:Timer?

	private let iconView=NSImageView()
	private let titleLabel=NSTextField(labelWithString:"")
	private let detailLabel=NSTextField(labelWithString:"")
	private let progressBar=NSProgressIndicator()
	private let statsLabel=NSTextField(labelWithString:"")

	/// Transfers shorter than this never show a panel at all — they would only
	/// flash on screen for a few frames.
	private let showDelay:TimeInterval=0.35
	/// How long the finished bar lingers before fading away.
	private let hideDelay:TimeInterval=1.2

	private static let byteFormatter:ByteCountFormatter={
		let formatter=ByteCountFormatter()
		formatter.countStyle = .file
		formatter.allowedUnits = [.useKB, .useMB, .useGB]
		return formatter
	}()

	private init(){}

	// MARK: - Transfer lifecycle

	/// Creates the transfer on its first report and updates it afterwards.
	func update(id:String, deviceName:String, detail:String, direction:TransferDirection, transferred:Int64, total:Int64){
		hideWorkItem?.cancel()
		hideWorkItem=nil

		if var transfer=transfers[id]{
			transfer.deviceName=deviceName
			transfer.detail=detail
			transfer.sample(transferred: transferred, total: total)
			transfers[id]=transfer
		}else{
			transfers[id]=ActiveTransfer(id: id, deviceName: deviceName, detail: detail, direction: direction, transferred: transferred, total: total)
			order.append(id)
			scheduleShow()
		}
		refresh()
	}

	/// Drops a transfer — on completion, failure or cancellation.
	func finish(id:String){
		guard transfers.removeValue(forKey: id) != nil else {return}
		order.removeAll {$0==id}
		refresh()
		if transfers.isEmpty{
			scheduleHide()
		}
	}

	// MARK: - Show / hide

	private func scheduleShow(){
		guard showWorkItem==nil, let id=order.last else {return}
		let item=DispatchWorkItem { [weak self] in
			guard let self=self else {return}
			self.showWorkItem=nil
			guard self.transfers[id] != nil else {return}
			self.showPanel()
		}
		showWorkItem=item
		DispatchQueue.main.asyncAfter(deadline: .now()+showDelay, execute: item)
	}

	private func scheduleHide(){
		hideWorkItem?.cancel()
		let item=DispatchWorkItem { [weak self] in
			guard let self=self else {return}
			self.hideWorkItem=nil
			guard self.transfers.isEmpty else {return}
			self.hidePanel()
		}
		hideWorkItem=item
		DispatchQueue.main.asyncAfter(deadline: .now()+hideDelay, execute: item)
	}

	private func showPanel(){
		let panel=ensurePanel()
		position(panel)
		startRefreshTimer()
		guard panel.alphaValue<1 else {return}
		panel.alphaValue=0
		panel.orderFrontRegardless()
		NSAnimationContext.runAnimationGroup { context in
			context.duration=0.15
			panel.animator().alphaValue=1
		}
	}

	private func hidePanel(){
		stopRefreshTimer()
		report(percent: nil)
		guard let panel=panel else {return}
		NSAnimationContext.runAnimationGroup({ context in
			context.duration=0.25
			panel.animator().alphaValue=0
		}, completionHandler: {
			panel.orderOut(nil)
		})
	}

	private func position(_ panel:NSPanel){
		guard let screen=NSScreen.main ?? NSScreen.screens.first else {return}
		let visible=screen.visibleFrame
		let size=panel.frame.size
		panel.setFrameOrigin(NSPoint(x: visible.maxX-size.width-20, y: visible.minY+20))
	}

	// MARK: - Refreshing

	private func startRefreshTimer(){
		guard refreshTimer==nil else {return}
		// The timer keeps the rate honest (and the estimate counting down) even
		// while no new chunk has arrived.
		let timer=Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
			self?.tick()
		}
		RunLoop.main.add(timer, forMode: .common)
		refreshTimer=timer
	}

	private func stopRefreshTimer(){
		refreshTimer?.invalidate()
		refreshTimer=nil
	}

	private func tick(){
		guard let id=order.last, var transfer=transfers[id] else {return}
		transfer.decaySpeed(ifIdleFor: 1.5)
		transfers[id]=transfer
		refresh()
	}

	private var reportedPercent:Int?=nil

	private func report(percent:Int?){
		guard reportedPercent != percent else {return}
		reportedPercent=percent
		onPercentChanged?(percent)
	}

	private func refresh(){
		guard let id=order.last, let transfer=transfers[id] else {
			report(percent: nil)
			return
		}
		titleLabel.stringValue=String(format: transfer.direction.headline, transfer.deviceName)
		detailLabel.stringValue=transfer.detail
		progressBar.doubleValue=transfer.fraction
		statsLabel.stringValue=statsText(for: transfer)
		report(percent: Int((transfer.fraction*100).rounded()))
	}

	private func statsText(for transfer:ActiveTransfer)->String{
		let done=byteString(transfer.transferred)
		guard transfer.total>0 else {return done}
		var parts=["\(done) / \(byteString(transfer.total))"]
		guard transfer.speed>1024 else {return parts.joined(separator: " · ")}
		parts.append(String(format: NSLocalizedString("Transfer.Rate", value: "%@/s", comment: ""), byteString(Int64(transfer.speed))))
		let seconds=Double(transfer.total-transfer.transferred)/transfer.speed
		if seconds>0.5 && seconds<3600{
			parts.append(String(format: NSLocalizedString("Transfer.TimeLeft", value: "%@ left", comment: ""), timeString(seconds)))
		}
		return parts.joined(separator: " · ")
	}

	private func byteString(_ bytes:Int64)->String{
		TransferProgressController.byteFormatter.string(fromByteCount: max(0, bytes))
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

	// MARK: - Panel

	private func ensurePanel()->NSPanel{
		if let panel=panel{
			return panel
		}
		let panel=NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 116),
		                  styleMask: [.borderless, .nonactivatingPanel],
		                  backing: .buffered,
		                  defer: false)
		panel.isOpaque=false
		panel.backgroundColor = .clear
		panel.hasShadow=true
		panel.level = .floating
		panel.hidesOnDeactivate=false
		panel.isReleasedWhenClosed=false
		panel.isMovableByWindowBackground=true
		panel.collectionBehavior=[.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

		let backdrop=NSVisualEffectView()
		backdrop.material = .popover
		backdrop.blendingMode = .behindWindow
		backdrop.state = .active
		backdrop.wantsLayer=true
		backdrop.layer?.cornerRadius=14
		backdrop.layer?.masksToBounds=true
		panel.contentView=backdrop

		iconView.image=NSApp.applicationIconImage
		iconView.imageScaling = .scaleProportionallyUpOrDown
		titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
		titleLabel.lineBreakMode = .byTruncatingTail
		detailLabel.font = .systemFont(ofSize: 11)
		detailLabel.textColor = .secondaryLabelColor
		detailLabel.lineBreakMode = .byTruncatingMiddle
		progressBar.isIndeterminate=false
		progressBar.style = .bar
		progressBar.controlSize = .small
		progressBar.minValue=0
		progressBar.maxValue=1
		statsLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
		statsLabel.textColor = .secondaryLabelColor
		statsLabel.lineBreakMode = .byTruncatingTail

		for view in [iconView, titleLabel, detailLabel, progressBar, statsLabel] as [NSView]{
			view.translatesAutoresizingMaskIntoConstraints=false
			backdrop.addSubview(view)
		}

		NSLayoutConstraint.activate([
			iconView.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor, constant: 16),
			iconView.topAnchor.constraint(equalTo: backdrop.topAnchor, constant: 16),
			iconView.widthAnchor.constraint(equalToConstant: 32),
			iconView.heightAnchor.constraint(equalToConstant: 32),

			titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
			titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: backdrop.trailingAnchor, constant: -16),
			titleLabel.topAnchor.constraint(equalTo: iconView.topAnchor, constant: 1),

			detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
			detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: backdrop.trailingAnchor, constant: -16),
			detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),

			progressBar.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor, constant: 16),
			progressBar.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor, constant: -16),
			progressBar.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 14),

			statsLabel.leadingAnchor.constraint(equalTo: progressBar.leadingAnchor),
			statsLabel.trailingAnchor.constraint(equalTo: progressBar.trailingAnchor),
			statsLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 8),
		])

		self.panel=panel
		refresh()
		return panel
	}
}
