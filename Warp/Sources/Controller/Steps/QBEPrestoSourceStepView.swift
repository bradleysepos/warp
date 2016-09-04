/* Warp. Copyright (C) 2014-2016 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import Foundation
import WarpCore

internal class QBEPrestoSourceStepView: QBEConfigurableStepViewControllerFor<QBEPrestoSourceStep>, NSTableViewDataSource, NSTableViewDelegate, NSComboBoxDataSource, NSComboBoxDelegate {
	var tableNames: [String]?
	var schemaNames: [String]?
	var catalogNames: [String]?
	@IBOutlet var tableView: NSTableView?
	@IBOutlet var urlField: NSTextField?
	@IBOutlet var catalogField: NSComboBox?
	@IBOutlet var schemaField: NSComboBox?

	required init?(configurable: QBEConfigurable, delegate: QBEConfigurableViewDelegate) {
		super.init(configurable: configurable, delegate: delegate, nibName: "QBEPrestoSourceStepView", bundle: nil)
	}
	
	required init?(coder: NSCoder) {
		fatalError("Should not be called")
	}
	
	internal override func viewWillAppear() {
		super.viewWillAppear()
		updateView()
	}
	
	@IBAction func update(_ sender: NSObject) {
		step.url = urlField?.stringValue ?? step.url
		step.catalogName = catalogField?.stringValue ?? step.catalogName
		step.schemaName = schemaField?.stringValue ?? step.schemaName
		updateView()
		self.delegate?.configurableView(self, didChangeConfigurationFor: step)
	}
	
	private func updateView() {
		let job = Job(.userInitiated)

		urlField?.stringValue = step.url 
		catalogField?.stringValue = step.catalogName 
		schemaField?.stringValue = step.schemaName 
		
		step.catalogNames(job) { (catalogsFallible) -> () in
			catalogsFallible.maybe {(catalogs) in
				asyncMain {
					self.catalogNames = Array(catalogs)
					self.catalogField?.reloadData()
				}
			}
		}
		
		step.schemaNames(job) { (schemasFallible) -> () in
			schemasFallible.maybe { (schemas) in
				asyncMain {
					self.schemaNames = Array(schemas)
					self.schemaField?.reloadData()
				}
			}
		}
		
		step.tableNames(job) { (namesFallible) -> () in
			namesFallible.maybe { (names) in
				asyncMain {
					self.tableNames = Array(names)
					self.tableView?.reloadData()
					
					if self.tableNames != nil {
						let currentTable = self.step.tableName
						for i in 0..<self.tableNames!.count {
							if self.tableNames![i]==currentTable {
								self.tableView?.selectRowIndexes(NSIndexSet(index: i) as IndexSet, byExtendingSelection: false)
								break
							}
						}
					}
				}
			}
		}
	}
	
	internal func tableViewSelectionDidChange(_ notification: Notification) {
		let selection = tableView?.selectedRow ?? -1
		if tableNames != nil && selection >= 0 && selection < tableNames!.count {
			let selectedName = tableNames![selection]
			step.tableName = selectedName
			delegate?.configurableView(self, didChangeConfigurationFor: step)
		}
	}
	
	func numberOfRows(in tableView: NSTableView) -> Int {
		return tableNames?.count ?? 0
	}
	
	internal func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
		return tableNames?[row] ?? ""
	}
	
	func numberOfItems(in aComboBox: NSComboBox) -> Int {
		if aComboBox == catalogField {
			return catalogNames?.count ?? 0
		}
		else if aComboBox == schemaField {
			return schemaNames?.count ?? 0
		}
		return 0
	}
	
	func comboBox(_ aComboBox: NSComboBox, objectValueForItemAt index: Int) -> Any? {
		if aComboBox == catalogField {
			return catalogNames?[index] ?? ""
		}
		else if aComboBox == schemaField {
			return schemaNames?[index] ?? ""
		}
		return ""
	}
}
