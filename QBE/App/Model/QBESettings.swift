import Foundation

/** QBESettings stores application-wide settings, primarily user preferences. These settings are currently stored in OS X
user defaults, but in the future may also be saved to iCloud or any other place. No security-sensitive information (e.g.
passwords) should be stored using QBESettings. **/
class QBESettings {
	static let sharedInstance = QBESettings()
	private let defaults: NSUserDefaults
	
	init () {
		defaults = NSUserDefaults.standardUserDefaults()
		
		#if DEBUG
			resetOnces()
		#endif
	}
	
	var locale: QBELocale.QBELanguage {
		get {
			return defaults.stringForKey("locale") ?? QBELocale.defaultLanguage
		}
	}
	
	var defaultFieldSeparator: String {
		get {
			return defaults.stringForKey("defaultSeparator") ?? ","
		}
	}
	
	var exampleMaximumTime: Double {
		get {
			return defaults.doubleForKey("exampleMaximumTime") ?? 1.5
		}
		
		set {
			defaults.setDouble(max(0.25, newValue), forKey: "exampleMaximumTime")
		}
	}
	
	var exampleMaximumRows: Int {
		get {
			return defaults.integerForKey("exampleMaximumRows") ?? 500
		}
		
		set {
			defaults.setInteger(max(100, newValue), forKey: "exampleMaximumRows")
		}
	}
	
	func defaultWidthForColumn(withName: QBEColumn) -> Double? {
		return defaults.doubleForKey("width.\(withName.name)")
	}
	
	func setDefaultWidth(width: Double, forColumn: QBEColumn) {
		defaults.setDouble(width, forKey: "width.\(forColumn.name)")
	}
	
	/** Return whether it is allowable to cache a file of the indicated size in the indicated location. This function
	bases its decision on the amount of disk space free in the target location (and allows any file to be cached to
	only use a particular fraction of it). In the future, it may use preferences exposed to the user. The result of this
	function should be used to set the default preference for caching in steps that allow the user to toggle caching.
	Caching explicitly requested by the user should be disabled anyway if this function returns false. **/
	func shouldCacheFile(ofEstimatedSize size: Int, atLocation: NSURL) -> Bool {
		// Let's find out how much disk space is left in the proposed cache location
		var error: NSError?
		if let attrs = NSFileManager.defaultManager().attributesOfFileSystemForPath(atLocation.path!, error: &error) {
			if let freeSpace = attrs[NSFileSystemFreeSize] as? NSNumber {
				let freeSize = Double(size) / Double(freeSpace)
				if freeSize < 0.8 {
					return true
				}
			}
		}
		return false
	}
	
	/** Call the provided callback only when this function has not been called before with the same key. This can be used
	to show the user certain things (such as tips) only once. **/
	func once(key: String, callback: () -> ()) {
		let onceKey = "once.\(key)"
		if !defaults.boolForKey(onceKey) {
			defaults.setBool(true, forKey: onceKey)
			callback()
		}
	}
	
	func resetOnces() {
		/* In debug builds, all keys starting with "once." are removed, to re-enable all 'once' actions such as
		first-time tips. */
		let dict = defaults.dictionaryRepresentation()
		for (key, value) in dict {
			let keyString = key.description
			if let r = keyString.rangeOfString("once.", options: NSStringCompareOptions.CaseInsensitiveSearch, range: nil, locale: nil) where r.startIndex==keyString.startIndex {
				defaults.removeObjectForKey(keyString)
			}
		}
	}
}