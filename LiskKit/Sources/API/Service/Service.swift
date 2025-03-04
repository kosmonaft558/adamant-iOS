//
//  Service.swift
//  LiskKit
//
//  Created by Anton Boyarkin on 15.08.2021.
//

import Foundation

public struct Service: APIService {
    
    public enum Version: String {
        case v1 = "v1"
        case v2 = "v2"
    }

    /// Client used to send requests
    public let client: APIClient
    public var version: Version = .v1

    /// Init
    public init(client: APIClient = .shared, version: Version = .v1) {
        self.init(client: client)
        self.version = version
    }
    
    public init(client: APIClient = .shared) {
        self.client = client
    }
}

// MARK: - List

extension Service {

    public func getFees(completionHandler: @escaping (Response<ServiceFeeResponse>) -> Void) {
        client.get(path: "\(Version.v2.rawValue)/fees", completionHandler: completionHandler)
    }

    /// List transaction objects
    public func transactions(id: String? = nil, block: String? = nil, sender: String? = nil, recipient: String? = nil, senderIdOrRecipientId: String? = nil, limit: UInt? = nil, offset: UInt? = nil, sort: APIRequest.Sort? = nil, completionHandler: @escaping (Result<[Transactions.TransactionModel]>) -> Void) {
        if version == .v1 {
            transactionsV1(id: id, block: block, sender: sender, recipient: recipient, senderIdOrRecipientId: senderIdOrRecipientId, limit: limit, offset: offset, sort: sort) { result in
                switch result {
                case .success(response: let value):
                    completionHandler(.success(response: value.data))
                case .error(response: let error):
                    completionHandler(.error(response: error))
                }
            }
        } else {
            transactionsV2(id: id, block: block, sender: sender, recipient: recipient, senderIdOrRecipientId: senderIdOrRecipientId, limit: limit, offset: offset, sort: sort) { result in
                switch result {
                case .success(response: let value):
                    let transaction = value.data.map {
                        Transactions.TransactionModel(id: $0.id,
                                                      height: $0.height,
                                                      blockId: $0.blockId,
                                                      type: $0.type,
                                                      timestamp: $0.timestamp,
                                                      senderPublicKey: $0.senderPublicKey,
                                                      senderId: $0.senderId,
                                                      recipientId: $0.recipientId,
                                                      recipientPublicKey: $0.recipientPublicKey,
                                                      amount: $0.amount,
                                                      fee: $0.fee,
                                                      signature: $0.signature,
                                                      confirmations: $0.confirmations)
                    }
                    completionHandler(.success(response: transaction))
                case .error(response: let error):
                    completionHandler(.error(response: error))
                }
            }
        }
    }
    
    private func transactionsV1(id: String? = nil, block: String? = nil, sender: String? = nil, recipient: String? = nil, senderIdOrRecipientId: String? = nil, limit: UInt? = nil, offset: UInt? = nil, sort: APIRequest.Sort? = nil, completionHandler: @escaping (Response<Transactions.TransactionsResponse>) -> Void) {
        var options: RequestOptions = [:]
        if let value = id { options["id"] = value }
        if let value = block { options["blockId"] = value }
        if let value = limit { options["limit"] = value }
        if let value = offset { options["offset"] = value }
        if let value = sort?.value { options["sort"] = value }
        if let value = sender { options["senderId"] = value }
        if let value = recipient { options["recipientId"] = value }
        if let value = senderIdOrRecipientId { options["senderIdOrRecipientId"] = value }

        client.get(path: "\(Version.v1.rawValue)/transactions", options: options, completionHandler: completionHandler)
    }
    
    private func transactionsV2(id: String? = nil, block: String? = nil, sender: String? = nil, recipient: String? = nil, senderIdOrRecipientId: String? = nil, limit: UInt? = nil, offset: UInt? = nil, sort: APIRequest.Sort? = nil, completionHandler: @escaping (Response<ServiceTransactionsResponse>) -> Void) {
        var options: RequestOptions = [:]
        if let value = id { options["transactionId"] = value }
        if let value = block { options["blockId"] = value }
        if let value = limit { options["limit"] = value }
        if let value = offset { options["offset"] = value }
        if let value = sort?.value { options["sort"] = value }
        if let value = sender { options["senderAddress"] = value }
        if let value = recipient { options["recipientAddress"] = value }
        if let value = senderIdOrRecipientId { options["address"] = value }

        client.get(path: "\(Version.v2.rawValue)/transactions", options: options, completionHandler: completionHandler)
    }
}
