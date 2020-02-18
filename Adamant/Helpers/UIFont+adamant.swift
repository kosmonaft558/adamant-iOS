//
//  UIFont+adamant.swift
//  Adamant
//
//  Created by Anokhov Pavel on 13.07.2018.
//  Copyright © 2018 Adamant. All rights reserved.
//

import UIKit

extension UIFont {
    static func adamantPrimary(ofSize size: CGFloat) -> UIFont {
        return UIFont(name: "Exo 2", size: size)!
    }
    
    static func adamantPrimary(ofSize size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let name: String
        
        switch weight {
        case UIFont.Weight.bold:
            name = "Exo 2 Bold"
            
        case UIFont.Weight.medium:
            name = "Exo 2 Medium"
            
        case UIFont.Weight.thin:
            name = "Exo 2 Thin"
            
        case UIFont.Weight.light:
            name = "Exo 2 Light"
            
        default:
            name = "Exo 2"
        }
        
        return UIFont(name: name, size: size)!
    }
    
    static var adamantChatDefault = UIFont.systemFont(ofSize: 17)
}
