//
//  Chatroom+CoreDataClass.swift
//  Adamant
//
//  Created by Anokhov Pavel on 10/11/2018.
//  Copyright © 2018 Adamant. All rights reserved.
//
//

import Foundation
import CoreData

@objc(Chatroom)
public class Chatroom: NSManagedObject {
    static let entityName = "Chatroom"
    
    func markAsReaded() {
        hasUnreadMessages = false
       
        if let trs = transactions as? Set<ChatTransaction> {
            trs.filter { $0.isUnread }.forEach { $0.isUnread = false }
        }
        lastTransaction?.isUnread = false
    }
    
    func getFirstUnread() -> ChatTransaction? {
        if let trs = transactions as? Set<ChatTransaction> {
            return trs.filter { $0.isUnread }.map { $0 }.first
        }
        return nil
    }
    
    @MainActor func getName(addressBookService: AddressBookService) -> String? {
        guard let partner = partner else { return nil }
        let result: String?
        if let title = title {
            result = title
        } else if let name = partner.name {
            result = name
        } else if
            let address = partner.address,
            let name = addressBookService.getName(for: address)
        {
            result = name
        } else {
            result = partner.address
        }
        
        return result?.checkAndReplaceSystemWallets()
    }
    
    private var semaphore: DispatchSemaphore?
    
    func updateLastTransaction() {
        var semaphore = self.semaphore
        
        if let semaphore = semaphore {
            semaphore.wait()
        } else {
            semaphore = DispatchSemaphore(value: 1)
        }
        
        self.semaphore = semaphore
        defer {
            self.semaphore = nil
            semaphore?.signal()
        }
        
        if let transactions = transactions?.filtered(using: NSPredicate(format: "isHidden == false")) as? Set<ChatTransaction> {
            if let newest = transactions.sorted(by: { (lhs: ChatTransaction, rhs: ChatTransaction) in
                guard let l = lhs.date as Date? else {
                    return true
                }
                
                guard let r = rhs.date as Date? else {
                    return false
                }
                
                switch l.compare(r) {
                case .orderedAscending:
                    return true
                    
                case .orderedDescending:
                    return false
                    
                // Rare case of identical date, compare IDs
                case .orderedSame:
                    return lhs.transactionId < rhs.transactionId
                }
            }).last {
                if newest != lastTransaction {
                    lastTransaction = newest
                    updatedAt = newest.date
                }
            } else if lastTransaction != nil {
                lastTransaction = nil
                updatedAt = nil
            }
        }
    }
    
    @MainActor
    func updateLastTransaction() async {
        if let transactions = transactions?.filtered(
            using: NSPredicate(format: "isHidden == false")
        ) as? Set<ChatTransaction> {
            if let newest = transactions.sorted(by: { (lhs: ChatTransaction, rhs: ChatTransaction) in
                guard let l = lhs.date as Date? else {
                    return true
                }
                
                guard let r = rhs.date as Date? else {
                    return false
                }
                
                switch l.compare(r) {
                case .orderedAscending:
                    return true
                    
                case .orderedDescending:
                    return false
                    
                // Rare case of identical date, compare IDs
                case .orderedSame:
                    return lhs.transactionId < rhs.transactionId
                }
            }).last {
                if newest != lastTransaction {
                    lastTransaction = newest
                    updatedAt = newest.date
                }
            } else if lastTransaction != nil {
                lastTransaction = nil
                updatedAt = nil
            }
        }
    }
}
