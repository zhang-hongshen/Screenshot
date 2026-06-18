//
//  Item.swift
//  Screenshot
//
//  Created by 张鸿燊 on 18/6/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
