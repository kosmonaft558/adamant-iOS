//
//  LocalTransaction.swift
//  Lisk
//
//  Created by Andrew Barba on 1/7/18.
//

import Foundation
import JavaScriptCore

infix operator >>> : BitwiseShiftPrecedence

func >>> (lhs: Int64, rhs: Int64) -> Int64 {
    return Int64(bitPattern: UInt64(bitPattern: lhs) >> UInt64(rhs))
}

internal func generateKey(for fieldNumber: UInt32, with wireType: UInt32) -> [UInt8] {
    let value = (fieldNumber << 3) | wireType
    let hValue = writeUInt32(value)
    return hValue //(Data() + hValue).bytes
}

let msg: UInt8 = 0x80
let rest: UInt32 = 0x7f

internal func writeUInt32(_ value: UInt32) -> [UInt8] {
    var result = [UInt8]()
    var value = value
    var index = 0
    while (value > rest) {
        result.append(msg | UInt8((Int64((value & rest)) >>> 0)))
        value = UInt32((Int64(value) >>> 7) >>> 0)
        index += 1
    }

    result.append(UInt8(value))
    return result
}

internal func writeUInt64(_ value: UInt64) -> [UInt8] {
    var result = [UInt8]()
    var value = value
    var index = 0
    while (value > UInt64(rest)) {
        result.append(msg | UInt8((Int64((value & UInt64(rest))) )))
        value = UInt64(Int64(value) >>> 7)
        index += 1
    }

    result.append(UInt8(value))
    return result
}

extension Data {
    var bytes: [UInt8] {
        let count = self.count / MemoryLayout<UInt8>.size
         var byteArray = [UInt8](repeating: 0, count: count)
        self.copyBytes(to: &byteArray, count:count)
        return byteArray
      }
}

public struct TransactionEntity {

    public struct Asset {
        public var amount: UInt64
        public var recipientAddress: String
        public var data: String = ""
        
        public func bytes() -> [UInt8] {
            var value = Data()
            value += generateKey(for: 1, with: 0)
            value += writeUInt64(amount)
            value += generateKey(for: 2, with: 2)
            value += writeUInt32(UInt32(recipientAddress.allHexBytes().count))
            value += recipientAddress.allHexBytes()
            value += generateKey(for: 3, with: 2)
            value += writeUInt32(UInt32(data.bytes.count))
            if data.count > 0 {
                value += data
            }
            return value.bytes
        }
        
        public var requestOptions: RequestOptions {
            let options: RequestOptions = [
                "amount": "\(amount)",
                "recipientAddress": recipientAddress,
                "data": data
            ]
            
            return options
        }
    }
    public var id: String = ""
    public var moduleID: UInt32 = 2
    public var assetID: UInt32 = 0
    public var fee: UInt64
    public var nonce: UInt64
    public var senderPublicKey: String
    public var asset: Asset
    public var signatures: [String] = []

    internal init(moduleID: UInt32 = 2, assetID: UInt32 = 0, fee: UInt64 = 0, nonce: UInt64, senderPublicKey: String, asset: TransactionEntity.Asset, signatures: [String] = []) {
        self.moduleID = moduleID
        self.assetID = assetID
        self.fee = fee
        self.nonce = nonce
        self.senderPublicKey = senderPublicKey
        self.asset = asset
        self.signatures = signatures
    }

    public init(amount: Decimal, fee: Decimal, nonce: String, senderPublicKey: String, recipientAddress: String) {
        let amount = Crypto.fixedPoint(amount: amount)
        let fee = Crypto.fixedPoint(amount: fee)
        self.init(amount: amount, fee: fee, nonce: nonce, senderPublicKey: senderPublicKey, recipientAddress: recipientAddress)
    }

    public init(amount: UInt64, fee: UInt64, nonce: String, senderPublicKey: String, recipientAddress: String, signatures: [String] = []) {
        self.fee = fee
        self.nonce = UInt64(nonce) ?? 0
        self.senderPublicKey = senderPublicKey
        self.asset = .init(amount: amount, recipientAddress: recipientAddress)
        self.signatures = signatures
    }
    
    public func bytes() -> [UInt8] {
        var value = Data()
        value += generateKey(for: 1, with: 0)
        value += writeUInt32(moduleID)
        value += generateKey(for: 2, with: 0)
        value += writeUInt32(assetID)
        value += generateKey(for: 3, with: 0)
        value += writeUInt64(nonce)
        value += generateKey(for: 4, with: 0)
        value += writeUInt64(fee)
        
        value += generateKey(for: 5, with: 2)
        value += writeUInt32(UInt32(senderPublicKey.allHexBytes().count))
        value += senderPublicKey.allHexBytes()
        value += generateKey(for: 6, with: 2)
        let assetBytes = asset.bytes()
        value += writeUInt32(UInt32(assetBytes.count))
        value += assetBytes
        
        if !signatures.isEmpty {
            signatures.forEach { sign in
                value += generateKey(for: 7, with: 2)
                value += writeUInt32(UInt32(sign.allHexBytes().count))
                value += sign.allHexBytes()
            }
        }
        
        return value.bytes
    }
    
    public func signature(with keyPair: KeyPair, for netHash: String) -> String {
        let bytesArray = bytes()
        let bytes = netHash.allHexBytes() + bytesArray
        
        let signBytes = keyPair.sign(bytes)
        let sign = signBytes.hexString()
        return sign
    }
    
    public func signed(with keyPair: KeyPair, for netHash: String) -> TransactionEntity {
        return TransactionEntity(fee: fee,
                                 nonce: nonce,
                                 senderPublicKey: senderPublicKey,
                                 asset: asset,
                                 signatures: [signature(with: keyPair, for: netHash)])
    }

    public func getFee(with minFeePerByte: UInt64) -> UInt64 {
        let bytesCount = bytes().count
        return UInt64(bytesCount) * minFeePerByte
    }

    public func updated(with minFeePerByte: UInt64) -> TransactionEntity {
        return TransactionEntity(fee: getFee(with: minFeePerByte),
                                 nonce: nonce,
                                 senderPublicKey: senderPublicKey,
                                 asset: asset,
                                 signatures: signatures)
    }
    
    public var requestOptions: RequestOptions {
        let options: RequestOptions = [
            "moduleID": moduleID,
            "assetID": assetID,
            "fee": "\(fee)",
            "nonce": "\(nonce)",
            "senderPublicKey": senderPublicKey,
            "asset": asset.requestOptions,
            "signatures": signatures
        ]
        
        return options
    }
    
    public func validate(with netHash: String) -> Bool {
        guard let signature = signatures.first else { return false }

        let tagMessagge = "LSK_TX".bytes + netHash.hexBytes() + bytes()

        do {
            return try Crypto.verify(message: tagMessagge, signature: signature.hexBytes(), publicKey: senderPublicKey.hexBytes())
        } catch let error {
            print(error)
            return false
        }
    }
    
}

/// Struct to represent a local transaction with the ability to locally sign via a secret passphrase
public struct LocalTransaction {

    /// Transaction asset
    public typealias Asset = [String: Any]

    /// Type of transaction
    public let type: TransactionType

    /// Amount of Lisk to send
    public let amount: UInt64

    /// Fee to complete the transaction
    public let fee: UInt64

    /// The recipient of the amount being sent
    public let recipientId: String?

    /// Timestamp relative to Genesis epoch time
    public let timestamp: UInt32

    /// Additional transaction data
    public let asset: Asset?

    /// Id of the transaction, only set after the transaction is signed
    public private(set) var id: String?

    /// Public key extracted from secret, only set after the transaction is signed
    public private(set) var senderPublicKey: String?

    /// Signature of the transaction, only set after the transaction is signed
    public private(set) var signature: String?

    /// Second sign-signature of the transaction, only set after the transaction is signed
    public private(set) var signSignature: String?

    /// Has this transaction been signed already
    public var isSigned: Bool {
        return id != nil && senderPublicKey != nil && signature != nil
    }

    /// Has this transaction been signed with a secret and second secret
    public var isSecondSigned: Bool {
        return isSigned && signSignature != nil
    }

    /// Init
    public init(_ type: TransactionType, amount: UInt64, recipientId: String? = nil, timestamp: UInt32? = nil, asset: Asset? = nil) {
        self.type = type
        self.amount = amount
        self.fee = LocalTransaction.transactionFee(type: type)
        self.recipientId = recipientId
        self.timestamp = timestamp ?? Crypto.timeIntervalSinceGenesis()
        self.asset = asset
        self.id = nil
        self.senderPublicKey = nil
        self.signature = nil
        self.signSignature = nil
    }

    /// Init
    public init(_ type: TransactionType, lsk: Double, recipientId: String? = nil, timestamp: UInt32? = nil, asset: Asset? = nil) {
        let amount = Crypto.fixedPoint(amount: lsk)
        self.init(type, amount: amount, recipientId: recipientId, timestamp: timestamp, asset: asset)
    }

    /// Init, copies transaction
    public init(transaction: LocalTransaction) {
        self.type = transaction.type
        self.amount = transaction.amount
        self.fee = transaction.fee
        self.recipientId = transaction.recipientId
        self.senderPublicKey = transaction.senderPublicKey
        self.timestamp = transaction.timestamp
        self.asset = transaction.asset
        self.id = transaction.id
        self.signature = transaction.signature
        self.signSignature = transaction.signSignature
    }

    /// Returns a new signed transaction based on this transaction
    public func signed(passphrase: String, secondPassphrase: String? = nil) throws -> LocalTransaction {
        let keyPair = try Crypto.keyPair(fromPassphrase: passphrase)
        let secondKeyPair: KeyPair?
        if let secondPassphrase = secondPassphrase {
            secondKeyPair = try Crypto.keyPair(fromPassphrase: secondPassphrase)
        } else {
            secondKeyPair = nil
        }
        return try signed(keyPair: keyPair, secondKeyPair: secondKeyPair)
    }

    /// Signs the current transaction
    public mutating func sign(passphrase: String, secondPassphrase: String? = nil) throws {
        let transaction = try signed(passphrase: passphrase, secondPassphrase: secondPassphrase)
        self.id = transaction.id
        self.senderPublicKey = transaction.senderPublicKey
        self.signature = transaction.signature
        self.signSignature = transaction.signSignature
    }

    /// Returns a new signed transaction based on this transaction
    public func signed(keyPair: KeyPair, secondKeyPair: KeyPair? = nil) throws -> LocalTransaction {
        var transaction = LocalTransaction(transaction: self)
        transaction.senderPublicKey = keyPair.publicKeyString
        transaction.signature = LocalTransaction.generateSignature(bytes: transaction.bytes, keyPair: keyPair)
        if let secondKeyPair = secondKeyPair, transaction.type != .registerSecondPassphrase {
            transaction.signSignature = LocalTransaction.generateSignature(bytes: transaction.bytes, keyPair: secondKeyPair)
        }
        transaction.id = LocalTransaction.generateId(bytes: transaction.bytes)
        return transaction
    }

    /// Signs the current transaction
    public mutating func sign(keyPair: KeyPair, secondKeyPair: KeyPair? = nil) throws {
        let transaction = try signed(keyPair: keyPair, secondKeyPair: secondKeyPair)
        self.id = transaction.id
        self.senderPublicKey = transaction.senderPublicKey
        self.signature = transaction.signature
        self.signSignature = transaction.signSignature
    }

    private static func generateId(bytes: [UInt8]) -> String {
        let hash = SHA256(bytes).digest()
        let id = Crypto.byteIdentifier(from: hash)
        return "\(id)"
    }

    private static func generateSignature(bytes: [UInt8], keyPair: KeyPair) -> String {
        let hash = SHA256(bytes).digest()
        return keyPair.sign(hash).hexString()
    }

    private static func transactionFee(type: TransactionType) -> UInt64 {
        switch type {
        case .transfer: return Constants.Fee.transfer
        case .registerSecondPassphrase: return Constants.Fee.signature
        case .registerDelegate: return Constants.Fee.delegate
        case .castVotes: return Constants.Fee.vote
        case .registerMultisignature: return Constants.Fee.multisignature
        case .createDapp: return Constants.Fee.dapp
        case .transferIntoDapp: return Constants.Fee.inTransfer
        case .transferOutOfDapp: return Constants.Fee.outTransfer
        }
    }
}

// MARK: - Bytes

extension LocalTransaction {

    var bytes: [UInt8] {
        return
            typeBytes +
            timestampBytes +
            senderPublicKeyBytes +
            recipientIdBytes +
            amountBytes +
            assetBytes +
            signatureBytes +
            signSignatureBytes
    }

    var typeBytes: [UInt8] {
        return [type.rawValue]
    }

    var timestampBytes: [UInt8] {
        return BytePacker.pack(timestamp, byteOrder: .littleEndian)
    }

    var senderPublicKeyBytes: [UInt8] {
        return senderPublicKey?.hexBytes() ?? []
    }

    var recipientIdBytes: [UInt8] {
        guard
            let value = recipientId?.replacingOccurrences(of: "L", with: ""),
            let number = UInt64(value) else { return [UInt8](repeating: 0, count: 8) }
        return BytePacker.pack(number, byteOrder: .bigEndian)
    }

    var amountBytes: [UInt8] {
        return BytePacker.pack(amount, byteOrder: .littleEndian)
    }

    var signatureBytes: [UInt8] {
        return signature?.hexBytes() ?? []
    }

    var signSignatureBytes: [UInt8] {
        return signSignature?.hexBytes() ?? []
    }

    var assetBytes: [UInt8] {
        guard
            let data = asset as? [String: [String: String]],
            let signature = data["signature"],
            let publicKey = signature["publicKey"]
            else { return [] }
        return publicKey.hexBytes()
    }
}

// MARK: - Request Options

extension LocalTransaction {

    var requestOptions: RequestOptions {
        var options: RequestOptions = [
            "id": id ?? NSNull(),
            "type": type.rawValue,
            "amount": "\(amount)",
            "fee": "\(fee)",
            "recipientId": recipientId ?? NSNull(),
            "senderPublicKey": senderPublicKey ?? NSNull(),
            "timestamp": timestamp,
            "asset": asset ?? Asset(),
            "signature": signature ?? NSNull()
        ]
        
        if let value = signSignature { options["signSignature"] = value }
        
        return options
    }
}

protocol BinaryConvertible {
    static func +(lhs: Data, rhs: Self) -> Data
    static func +=(lhs: inout Data, rhs: Self)
}

extension BinaryConvertible {
    static func +(lhs: Data, rhs: Self) -> Data {
        var value = rhs
        let data = withUnsafePointer(to: &value) { ptr -> Data in
            return Data(buffer: UnsafeBufferPointer(start: ptr, count: 1))
        }
        return lhs + data
    }

    static func +=(lhs: inout Data, rhs: Self) {
        lhs = lhs + rhs
    }
}

extension UInt8: BinaryConvertible {}
extension UInt16: BinaryConvertible {}
extension UInt32: BinaryConvertible {}
extension UInt64: BinaryConvertible {}
extension Int8: BinaryConvertible {}
extension Int16: BinaryConvertible {}
extension Int32: BinaryConvertible {}
extension Int64: BinaryConvertible {}
extension Int: BinaryConvertible {}

extension Bool: BinaryConvertible {
    static func +(lhs: Data, rhs: Bool) -> Data {
        return lhs + (rhs ? UInt8(0x01) : UInt8(0x00)).littleEndian
    }
}

extension String: BinaryConvertible {
    static func +(lhs: Data, rhs: String) -> Data {
        guard let data = rhs.data(using: .utf8) else { return lhs }
        return lhs + data
    }
}

extension Data: BinaryConvertible {
    static func +(lhs: Data, rhs: Data) -> Data {
        var data = Data()
        data.append(lhs)
        data.append(rhs)
        return data
    }
}

extension Data {
    public init?(hex: String) {
        let len = hex.count / 2
        var data = Data(capacity: len)
        for i in 0..<len {
            let j = hex.index(hex.startIndex, offsetBy: i * 2)
            let k = hex.index(j, offsetBy: 2)
            let bytes = hex[j..<k]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
        }
        self = data
    }

    public var hex: String {
        return reduce("") { $0 + String(format: "%02x", $1) }
    }
}
