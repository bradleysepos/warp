import Foundation

internal let QBEExpressions: [QBEExpression.Type] = [
	QBESiblingExpression.self,
	QBELiteralExpression.self,
	QBEBinaryExpression.self,
	QBEFunctionExpression.self,
	QBEIdentityExpression.self
]

/** A QBEExpression is a 'formula' that evaluates to a certain QBEValue given a particular context. **/
class QBEExpression: NSObject, NSCoding {
	func explain(locale: QBELocale) -> String {
		return "??"
	}
	
	/** The complexity of an expression is an indication of how 'far fetched' it is - this is used by QBEInferer to 
	decide which expressions to suggest. **/
	var complexity: Int { get {
		return 1
	}}
	
	/** Returns whether the result of this expression is independent of the row fed to it. An expression that reports it
	is constant is guaranteed to return a value for apply() called without a row, set of columns and input value. **/
	var isConstant: Bool { get {
		return false
	} }
	
	/** Returns a version of this expression that has constant parts replaced with their actual values. **/
	func prepare() -> QBEExpression {
		if isConstant {
			return QBELiteralExpression(self.apply(QBERow(), foreign: nil, inputValue: nil))
		}
		return self
	}
	
	override init() {
	}
	
	required init(coder aDecoder: NSCoder) {
	}
	
	func encodeWithCoder(aCoder: NSCoder) {
	}
	
	/** Returns a localized representation of this expression, which should (when parsed by QBEFormula in the same locale)
	result in an equivalent expression. **/
	func toFormula(locale: QBELocale) -> String {
		return ""
	}
	
	/** Requests that callback be called on self, and visit() forwarded to all children. This can be used to implement
	dependency searches, etc. **/
	func visit(callback: (QBEExpression) -> ()) {
		callback(self)
	}
	
	/** Calculate the result of this expression for the given row, columns and current input value. **/
	func apply(row: QBERow, foreign: QBERow?, inputValue: QBEValue?) -> QBEValue {
		fatalError("A QBEExpression was called that isn't implemented")
	}
	
	/** Returns a list of suggestions for applications of this expression on the given value (fromValue) that result in the
	given 'to' value (or bring the value closer to the toValue). **/
	class func suggest(fromValue: QBEExpression?, toValue: QBEValue, row: QBERow, inputValue: QBEValue?, level: Int, job: QBEJob?) -> [QBEExpression] {
		return []
	}
	
	/** The infer function implements an algorithm to find one or more formulas that are able to transform an
	input value to a specific output value. It does so by looping over 'suggestions' (provided by QBEFunction
	implementations) for the application of (usually unary) functions to the input value to obtain (or come closer to) the
	output value. **/
	internal class final func infer(fromValue: QBEExpression?, toValue: QBEValue, inout suggestions: [QBEExpression], level: Int, row: QBERow, column: Int, maxComplexity: Int = Int.max, previousValues: [QBEValue] = [], job: QBEJob? = nil) {
		let inputValue = row.values[column]
		if let c = job?.cancelled where c {
			return
		}
		
		// Try out combinations of formulas and see if they fit
		for formulaType in QBEExpressions {
			if let c = job?.cancelled where c {
				return
			}
			
			let suggestedFormulas = formulaType.suggest(fromValue, toValue: toValue, row: row, inputValue: inputValue, level: level, job: job);
			var complexity = maxComplexity
			var exploreFurther: [QBEExpression] = []
			
			for formula in suggestedFormulas {
				if formula.complexity >= maxComplexity {
					continue
				}
				
				let result = formula.apply(row, foreign: nil, inputValue: inputValue)
				if result == toValue {
					suggestions.append(formula)
					
					if formula.complexity < maxComplexity {
						complexity = formula.complexity
					}
				}
				else {
					if level > 0 {
						exploreFurther.append(formula)
					}
				}
			}
			
			if suggestions.count == 0 {
				// Let's see if we can find something else
				for formula in exploreFurther {
					let result = formula.apply(row, foreign: nil, inputValue: inputValue)
					
					// Have we already seen this result? Then ignore
					var found = false
					for previous in previousValues {
						if previous == result {
							found = true
							break
						}
					}
					
					if found {
						continue
					}
					
					var nextLevelSuggestions: [QBEExpression] = []
					var newPreviousValues = previousValues
					newPreviousValues.append(result)
					infer(formula, toValue: toValue, suggestions: &nextLevelSuggestions, level: level-1, row: row, column: column, maxComplexity: complexity, previousValues: newPreviousValues, job: job)
					
					for nextLevelSuggestion in nextLevelSuggestions {
						if nextLevelSuggestion.apply(row, foreign: nil, inputValue: inputValue) == toValue {
							if nextLevelSuggestion.complexity <= complexity {
								suggestions.append(nextLevelSuggestion)
								complexity = nextLevelSuggestion.complexity
							}
						}
					}
				}
			}
		}
	}
}

/** The QBELiteralExpression always evaluates to the value set to it on initialization. The formula parser generates a 
QBELiteralExpression for each literal (numbers, strings, constants) it encounters. **/
class QBELiteralExpression: QBEExpression {
	let value: QBEValue
	
	init(_ value: QBEValue) {
		self.value = value
		super.init()
	}
	
	override var complexity: Int { get {
		return 10
	}}
	
	override var isConstant: Bool { get {
		return true
	} }
	
	required init(coder aDecoder: NSCoder) {
		self.value = ((aDecoder.decodeObjectForKey("value") as? QBEValueCoder) ?? QBEValueCoder()).value
		super.init(coder: aDecoder)
	}
	
	override func explain(locale: QBELocale) -> String {
		return locale.localStringFor(value)
	}
	
	override func toFormula(locale: QBELocale) -> String {
		switch value {
		case .StringValue(let s):
			let escaped = value.stringValue!.stringByReplacingOccurrencesOfString(String(locale.stringQualifier), withString: locale.stringQualifierEscape)
			return "\(locale.stringQualifier)\(escaped)\(locale.stringQualifier)"
			
		case .DoubleValue(let d):
			// FIXME: needs to use decimalSeparator from locale
			return "\(d)"
			
		case .BoolValue(let b):
			return locale.constants[QBEValue(b)]!
			
		case .IntValue(let i):
			return "\(i)"
		
		case .InvalidValue: return locale.constants[QBEValue.EmptyValue]!
		case .EmptyValue: return locale.constants[QBEValue.EmptyValue]!
		}
	}
	
	override func encodeWithCoder(aCoder: NSCoder) {
		aCoder.encodeObject(QBEValueCoder(self.value), forKey: "value")
		super.encodeWithCoder(aCoder)
	}
	
	override func apply(row: QBERow, foreign: QBERow?, inputValue: QBEValue?) -> QBEValue {
		return value
	}
	
	override class func suggest(fromValue: QBEExpression?, toValue: QBEValue, row: QBERow, inputValue: QBEValue?, level: Int, job: QBEJob?) -> [QBEExpression] {
		if fromValue == nil {
			return [QBELiteralExpression(toValue)]
		}
		return []
	}
}

/** The QBEIdentityExpression returns whatever value was set to the inputValue parameter during evaluation. This value
usually represents the (current) value in the current cell. **/
class QBEIdentityExpression: QBEExpression {
	override init() {
		super.init()
	}
	
	override func explain(locale: QBELocale) -> String {
		return NSLocalizedString("current value", comment: "")
	}

	override func toFormula(locale: QBELocale) -> String {
		return locale.currentCellIdentifier
	}
	
	required init(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
	}
	
	override func apply(row: QBERow, foreign: QBERow?, inputValue: QBEValue?) -> QBEValue {
		return inputValue ?? QBEValue.InvalidValue
	}
}

/** QBEBinaryExpression evaluates to the result of applying a particular binary operator to two operands, which are 
other expressions. **/
class QBEBinaryExpression: QBEExpression {
	let first: QBEExpression
	let second: QBEExpression
	var type: QBEBinary
	
	override var isConstant: Bool { get {
		return first.isConstant && second.isConstant
	} }
	
	override func prepare() -> QBEExpression {
		let firstOptimized = first.prepare()
		let secondOptimized = second.prepare()
		let optimized = QBEBinaryExpression(first: firstOptimized, second: secondOptimized, type: self.type)
		if optimized.isConstant {
			return QBELiteralExpression(optimized.apply(QBERow(), foreign: nil, inputValue: nil))
		}
		return optimized
	}
	
	override func visit(callback: (QBEExpression) -> ()) {
		callback(self)
		first.visit(callback)
		second.visit(callback)
	}
	
	override func explain(locale: QBELocale) -> String {
		return "(" + second.explain(locale) + " " + type.explain(locale) + " " + first.explain(locale) + ")"
	}
	
	override func toFormula(locale: QBELocale) -> String {
		return "(\(second.toFormula(locale))\(type.toFormula(locale))\(first.toFormula(locale)))"
	}
	
	override var complexity: Int { get {
		return first.complexity + second.complexity + 1
		}}
	
	init(first: QBEExpression, second: QBEExpression, type: QBEBinary) {
		self.first = first
		self.second = second
		self.type = type
		super.init()
	}
	
	required init(coder aDecoder: NSCoder) {
		self.first = (aDecoder.decodeObjectForKey("first") as? QBEExpression) ?? QBEIdentityExpression()
		self.second = (aDecoder.decodeObjectForKey("second") as? QBEExpression) ?? QBEIdentityExpression()
		let typeString = (aDecoder.decodeObjectForKey("type") as? String) ?? QBEBinary.Addition.rawValue
		self.type = QBEBinary(rawValue: typeString) ?? QBEBinary.Addition
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(aCoder: NSCoder) {
		super.encodeWithCoder(aCoder)
		aCoder.encodeObject(first, forKey: "first")
		aCoder.encodeObject(second, forKey: "second")
		aCoder.encodeObject(type.rawValue, forKey: "type")
	}
	
	override func apply(row: QBERow, foreign: QBERow?, inputValue: QBEValue?) -> QBEValue {
		let left = second.apply(row, foreign: foreign, inputValue: nil)
		let right = first.apply(row, foreign: foreign, inputValue: nil)
		return self.type.apply(left, right)
	}
	
	override class func suggest(fromValue: QBEExpression?, toValue: QBEValue, row: QBERow, inputValue: QBEValue?, level: Int, job: QBEJob?) -> [QBEExpression] {
		var suggestions: [QBEExpression] = []
		
		if let from = fromValue {
			if let f = fromValue?.apply(row, foreign: nil, inputValue: inputValue) {
				if level > 1 {
					if let targetDouble = toValue.doubleValue {
						if let fromDouble = f.doubleValue {
							// Suggest addition or subtraction
							let difference = targetDouble - fromDouble
							if difference != 0 {
								var addSuggestions: [QBEExpression] = []
								QBEExpression.infer(nil, toValue: QBEValue(abs(difference)), suggestions: &addSuggestions, level: level-1, row: row, column: 0, maxComplexity: Int.max, previousValues: [toValue, f], job: job)
								
								if difference > 0 {
									addSuggestions.each({suggestions.append(QBEBinaryExpression(first: $0, second: from, type: QBEBinary.Addition))})
								}
								else {
									addSuggestions.each({suggestions.append(QBEBinaryExpression(first: $0, second: from, type: QBEBinary.Subtraction))})
								}
							}
							
							// Suggest division or multiplication
							if fromDouble != 0 {
								let dividend = targetDouble / fromDouble
								
								var mulSuggestions: [QBEExpression] = []
								QBEExpression.infer(nil, toValue: QBEValue(dividend < 1 ? (1/dividend) : dividend), suggestions: &mulSuggestions, level: level-1, row: row, column: 0, maxComplexity: Int.max, previousValues: [toValue, f], job: job)
								
								if dividend >= 1 {
									mulSuggestions.each({suggestions.append(QBEBinaryExpression(first: $0, second: from, type: QBEBinary.Multiplication))})
								}
								else {
									mulSuggestions.each({suggestions.append(QBEBinaryExpression(first: $0, second: from, type: QBEBinary.Division))})
								}
							}
						}
					}
					else if let targetString = toValue.stringValue, let fromString = f.stringValue {
						if !targetString.isEmpty && !fromString.isEmpty && count(fromString) < count(targetString) {
							// See if the target string shares a prefix with the source string
							let targetPrefix = targetString.substringWithRange(targetString.startIndex..<advance(targetString.startIndex, count(fromString)))
							if fromString == targetPrefix {
								let postfix = targetString.substringWithRange(advance(targetString.startIndex, count(fromString))..<targetString.endIndex)
								println("'\(fromString)' => '\(targetString)' share prefix: '\(targetPrefix)' need postfix: '\(postfix)'")
								
								var postfixSuggestions: [QBEExpression] = []
								QBEExpression.infer(nil, toValue: QBEValue.StringValue(postfix), suggestions: &postfixSuggestions, level: level-1, row: row, column: 0, maxComplexity: Int.max, previousValues: [toValue, f], job: job)
								
								postfixSuggestions.each({suggestions.append(QBEBinaryExpression(first: $0, second: from, type: QBEBinary.Concatenation))})
							}
							else {
								// See if the target string shares a postfix with the source string
								let prefixLength = count(targetString) - count(fromString)
								let targetPostfix = targetString.substringWithRange(advance(targetString.startIndex, prefixLength)..<targetString.endIndex)
								if fromString == targetPostfix {
									let prefix = targetString.substringWithRange(targetString.startIndex..<advance(targetString.startIndex, prefixLength))
									println("'\(fromString)' => '\(targetString)' share postfix: '\(targetPostfix)' need prefix: '\(prefix)'")
									
									var prefixSuggestions: [QBEExpression] = []
									QBEExpression.infer(nil, toValue: QBEValue.StringValue(prefix), suggestions: &prefixSuggestions, level: level-1, row: row, column: 0, maxComplexity: Int.max, previousValues: [toValue, f], job: job)
									
									prefixSuggestions.each({suggestions.append(QBEBinaryExpression(first: from, second: $0, type: QBEBinary.Concatenation))})
								}
							}
						}
					}
				}
			}
		}
		
		return suggestions
	}
}

/** QBEFunctionExpression evaluates to the result of applying a function to a given set of arguments. The set of arguments
consists of QBEExpressions that are evaluated before sending them to the function. **/
class QBEFunctionExpression: QBEExpression {
	let arguments: [QBEExpression]
	let type: QBEFunction
	
	override var isConstant: Bool { get {
		if !type.isDeterministic {
			return false
		}
		
		for a in arguments {
			if !a.isConstant {
				return false
			}
		}
		
		return true
	} }
	
	override func visit(callback: (QBEExpression) -> ()) {
		callback(self)
		arguments.each({$0.visit(callback)})
	}
	
	override func prepare() -> QBEExpression {
		return self.type.prepare(arguments)
	}
	
	override func explain(locale: QBELocale) -> String {
		let argumentsList = arguments.map({$0.explain(locale)}).implode(", ") ?? ""
		return "\(type.explain(locale))(\(argumentsList))"
	}
	
	override func toFormula(locale: QBELocale) -> String {
		let args = arguments.map({$0.toFormula(locale)}).implode(locale.argumentSeparator) ?? ""
		return "\(type.toFormula(locale))(\(args))"
	}
	
	override var complexity: Int { get {
		var complexity = 1
		for a in arguments {
			complexity = max(complexity, a.complexity)
		}
		
		return complexity + 1
	}}
	
	init(arguments: [QBEExpression], type: QBEFunction) {
		self.arguments = arguments
		self.type = type
		super.init()
	}
	
	required init(coder aDecoder: NSCoder) {
		self.arguments = (aDecoder.decodeObjectForKey("args") as? [QBEExpression]) ?? []
		let typeString = (aDecoder.decodeObjectForKey("type") as? String) ?? QBEFunction.Identity.rawValue
		self.type = QBEFunction(rawValue: typeString) ?? QBEFunction.Identity
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(aCoder: NSCoder) {
		super.encodeWithCoder(aCoder)
		aCoder.encodeObject(arguments, forKey: "args")
		aCoder.encodeObject(type.rawValue, forKey: "type")
	}
	
	override func apply(row: QBERow, foreign: QBERow?, inputValue: QBEValue?) -> QBEValue {
		let vals = arguments.map({$0.apply(row, foreign: foreign, inputValue: inputValue)})
		return self.type.apply(vals)
	}
	
	override class func suggest(fromValue: QBEExpression?, toValue: QBEValue, row: QBERow, inputValue: QBEValue?, level: Int, job: QBEJob?) -> [QBEExpression] {
		var suggestions: [QBEExpression] = []
		
		if let from = fromValue {
			if let f = fromValue?.apply(row, foreign: nil, inputValue: inputValue) {
				// Check whether one of the unary functions can transform the input value to the output value
				for op in QBEFunction.allFunctions {
					if(op.arity.valid(1)) {
						if op.apply([f]) == toValue {
							suggestions.append(QBEFunctionExpression(arguments: [from], type: op))
						}
					}
				}
				
				// For binary and n-ary functions, specific test cases follow
				var incompleteSuggestions: [QBEExpression] = []
				if let targetString = toValue.stringValue {
					let length = QBEValue(count(targetString))

					// Is the 'to' string perhaps a substring of the 'from' string?
					if let sourceString = f.stringValue {
						// Let's see if we can extract this string using array logic. Otherwise suggest index-based string splitting
						var foundAsElement = false
						let separators = [" ", ",", ";", "\t", "|", "-", ".", "/", ":", "\\", "#", "=", "_", "(", ")", "[", "]"]
						for separator in separators {
							if let c = job?.cancelled where c {
								break
							}
							
							let splitted = sourceString.componentsSeparatedByString(separator)
							if splitted.count > 1 {
								let pack = QBEPack(splitted)
								for i in 0..<pack.count {
									let item = pack[i]
									let splitExpression = QBEFunctionExpression(arguments: [from, QBELiteralExpression(QBEValue.StringValue(separator))], type: QBEFunction.Split)
									let nthExpression = QBEFunctionExpression(arguments: [splitExpression, QBELiteralExpression(QBEValue.IntValue(i+1))], type: QBEFunction.Nth)
									if targetString == item {
										suggestions.append(nthExpression)
										foundAsElement = true
									}
									else {
										incompleteSuggestions.append(nthExpression)
									}
									
								}
							}
						}

						if !foundAsElement {
							if incompleteSuggestions.count > 0 {
								suggestions += incompleteSuggestions
							}
							else {
								if let range = sourceString.rangeOfString(targetString) {
									suggestions.append(QBEFunctionExpression(arguments: [from, QBELiteralExpression(length)], type: QBEFunction.Left))
									suggestions.append(QBEFunctionExpression(arguments: [from, QBELiteralExpression(length)], type: QBEFunction.Right))
									
									let start = QBELiteralExpression(QBEValue(distance(sourceString.startIndex, range.startIndex)))
									let length = QBELiteralExpression(QBEValue(distance(range.startIndex, range.endIndex)))
									suggestions.append(QBEFunctionExpression(arguments: [from, start, length], type: QBEFunction.Mid))
								}
							}
						}
					}
				}
			}
		}
		
		return suggestions
	}
}

/** 
The QBESiblingExpression evaluates to the value of a cell in a particular column on the same row as the current value. */
class QBESiblingExpression: QBEExpression {
	var columnName: QBEColumn
	
	init(columnName: QBEColumn) {
		self.columnName = columnName
		super.init()
	}
	
	override func explain(locale: QBELocale) -> String {
		return NSLocalizedString("value in column", comment: "")+" "+columnName.name
	}
	
	required init(coder aDecoder: NSCoder) {
		columnName = QBEColumn((aDecoder.decodeObjectForKey("columnName") as? String) ?? "")
		super.init(coder: aDecoder)
	}
	
	override func toFormula(locale: QBELocale) -> String {
		return "[@\(columnName.name)]"
	}
	
	override func encodeWithCoder(aCoder: NSCoder) {
		super.encodeWithCoder(aCoder)
		aCoder.encodeObject(columnName.name, forKey: "columnName")
	}
	
	override func apply(row: QBERow, foreign: QBERow?, inputValue: QBEValue?) -> QBEValue {
		return row[columnName] ?? QBEValue.InvalidValue
	}
	
	override class func suggest(fromValue: QBEExpression?, toValue: QBEValue, row: QBERow, inputValue: QBEValue?, level: Int, job: QBEJob?) -> [QBEExpression] {
		var s: [QBEExpression] = []
		if fromValue == nil {
			for columnName in row.columnNames {
				s.append(QBESiblingExpression(columnName: columnName))
			}
		}
		return s
	}
}

/** 
The QBEForeignExpression evaluates to the value of a cell in a particular column in the foreign row. This is used to evaluate
whether two rows should be matched up in a join. If no foreign row is given, this expression gives an error. */
class QBEForeignExpression: QBEExpression {
	var columnName: QBEColumn
	
	init(columnName: QBEColumn) {
		self.columnName = columnName
		super.init()
	}
	
	override func explain(locale: QBELocale) -> String {
		return NSLocalizedString("value in foreign column", comment: "")+" "+columnName.name
	}
	
	required init(coder aDecoder: NSCoder) {
		columnName = QBEColumn((aDecoder.decodeObjectForKey("columnName") as? String) ?? "")
		super.init(coder: aDecoder)
	}
	
	override func toFormula(locale: QBELocale) -> String {
		return "[#\(columnName.name)]"
	}
	
	override func encodeWithCoder(aCoder: NSCoder) {
		super.encodeWithCoder(aCoder)
		aCoder.encodeObject(columnName.name, forKey: "columnName")
	}
	
	override func apply(row: QBERow, foreign: QBERow?, inputValue: QBEValue?) -> QBEValue {
		return foreign?[columnName] ?? QBEValue.InvalidValue
	}
	
	override class func suggest(fromValue: QBEExpression?, toValue: QBEValue, row: QBERow, inputValue: QBEValue?, level: Int, job: QBEJob?) -> [QBEExpression] {
		// TODO: implement when we are going to implement foreign suggestions
		return []
	}
}