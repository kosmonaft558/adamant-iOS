import Foundation
import BigInt
    
extension DashWalletService {
    // MARK: - Constants
    static let fixedFee: Decimal = 0.0001
    static let currencySymbol = "DASH"
    static let currencyExponent: Int = -8
    static let qqPrefix: String = "dash"
    
    static var newPendingInterval: Int {
        5000
    }
        
    static var oldPendingInterval: Int {
        3000
    }
        
    static var registeredInterval: Int {
        30000
    }
        
    static var newPendingAttempts: Int {
        20
    }
        
    static var oldPendingAttempts: Int {
        4
    }
        
    var tokenName: String {
        "Dash"
    }
    
    var consistencyMaxTime: Double {
        800
    }
    
    var minBalance: Decimal {
        0.0001
    }
    
    var minAmount: Decimal {
        2.0e-05
    }
    
    var defaultVisibility: Bool {
        true
    }
    
    var defaultOrdinalLevel: Int? {
        80
    }
    
    static let explorerAddress = "https://dashblockexplorer.com/tx/"
    
    static var nodes: [Node] {
        [
            Node(url: URL(string: "https://dashnode1.adamant.im")!),
        ]
    }
    
    static var serviceNodes: [Node] {
        [
            
        ]
    }
}
