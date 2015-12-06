import Cocoa
import WarpCore

internal extension CGRect {
	func inset(inset: CGFloat) -> CGRect {
		return CGRectMake(
			self.origin.x + inset,
			self.origin.y + inset,
			self.size.width - 2*inset,
			self.size.height - 2*inset
		)
	}
	
	var center: CGPoint {
		return CGPointMake(self.origin.x + self.size.width/2, self.origin.y + self.size.height/2)
	}
	
	func centeredAt(point: CGPoint) -> CGRect {
		return CGRectMake(point.x - self.size.width/2, point.y - self.size.height/2, self.size.width, self.size.height)
	}
	
	var rounded: CGRect { get {
		return CGRectMake(round(self.origin.x), round(self.origin.y), round(self.size.width), round(self.size.height))
	} }
}

internal extension CGPoint {
	func offsetBy(point: CGPoint) -> CGPoint {
		return CGPointMake(self.x + point.x, self.y + point.y)
	}
	
	func distanceTo(point: CGPoint) -> CGFloat {
		return hypot(point.x - self.x, point.y - self.y)
	}
}

internal extension NSAlert {
	static func showSimpleAlert(message: String, infoText: String, style: NSAlertStyle, window: NSWindow?) {
		QBEAssertMainThread()
		let av = NSAlert()
		av.messageText = message
		av.informativeText = infoText
		av.alertStyle = style

		if let w = window {
			av.beginSheetModalForWindow(w, completionHandler: nil)
		}
		else {
			av.runModal()
		}
	}
}

@IBDesignable class QBEBorderedView: NSView {
	@IBInspectable var leftBorder: Bool = false
	@IBInspectable var topBorder: Bool = false
	@IBInspectable var rightBorder: Bool = false
	@IBInspectable var bottomBorder: Bool = false
	@IBInspectable var backgroundColor: NSColor = NSColor.windowFrameColor() { didSet { self.setNeedsDisplayInRect(self.bounds) } }
	@IBInspectable var borderColor: NSColor = NSColor.windowFrameColor() { didSet { self.setNeedsDisplayInRect(self.bounds) } }
	
	override func drawRect(dirtyRect: NSRect) {
		backgroundColor.set()
		NSRectFill(self.bounds)

		let start = NSColor.controlBackgroundColor().colorWithAlphaComponent(0.7)
		let end = NSColor.controlBackgroundColor().colorWithAlphaComponent(0.6)
		let g = NSGradient(startingColor: start, endingColor: end)
		g?.drawInRect(self.bounds, angle: 270.0)

		borderColor.set()
		var bounds = self.bounds
		bounds.intersectInPlace(dirtyRect)
		
		if leftBorder {
			NSRectFill(CGRectMake(bounds.origin.x, bounds.origin.y, 1, bounds.size.height))
		}
		
		if rightBorder {
			NSRectFill(CGRectMake(bounds.origin.x + bounds.size.width, bounds.origin.y, 1, bounds.size.height))
		}
		
		if topBorder {
			NSRectFill(CGRectMake(bounds.origin.x, bounds.origin.y + bounds.size.height - 1, bounds.size.width, 1))
		}
		
		if bottomBorder {
			NSRectFill(CGRectMake(bounds.origin.x, bounds.origin.y, bounds.size.width, 1))
		}
	}
}

internal extension NSView {
	func orderFront() {
		self.superview?.addSubview(self)
	}
	
	func addSubview(view: NSView, animated: Bool, completion: (() -> ())? = nil) {
		if !animated {
			self.addSubview(view)
			return
		}
		
		let duration = 0.35
		view.wantsLayer = true
		self.addSubview(view)
		view.scrollRectToVisible(view.bounds)
		
		CATransaction.begin()
		CATransaction.setAnimationDuration(duration)
		CATransaction.setCompletionBlock(completion)
		let ta = CABasicAnimation(keyPath: "transform")
		
		// Scale, but centered in the middle of the view
		var begin = CATransform3DIdentity
		begin = CATransform3DTranslate(begin, view.bounds.size.width/2, view.bounds.size.height/2, 0.0)
		begin = CATransform3DScale(begin, 0.0, 0.0, 0.0)
		begin = CATransform3DTranslate(begin, -view.bounds.size.width/2, -view.bounds.size.height/2, 0.0)
		
		var end = CATransform3DIdentity
		end = CATransform3DTranslate(end, view.bounds.size.width/2, view.bounds.size.height/2, 0.0)
		end = CATransform3DScale(end, 1.0, 1.0, 0.0)
		end = CATransform3DTranslate(end, -view.bounds.size.width/2, -view.bounds.size.height/2, 0.0)
		
		// Fade in
		ta.fromValue = NSValue(CATransform3D: begin)
		ta.toValue = NSValue(CATransform3D: end)
		ta.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
		view.layer?.addAnimation(ta, forKey: "transformAnimation")
		
		let oa = CABasicAnimation(keyPath: "opacity")
		oa.fromValue = 0.0
		oa.toValue = 1.0
		oa.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
		view.layer?.addAnimation(oa, forKey: "opacityAnimation")
		
		CATransaction.commit()
	}
}