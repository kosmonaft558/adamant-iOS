//
//  EthWalletService+RichMessageProvider.swift
//  Adamant
//
//  Created by Anokhov Pavel on 08.09.2018.
//  Copyright © 2018 Adamant. All rights reserved.
//

import Foundation
import MessageKit

extension EthWalletService: RichMessageProvider {
    
    // MARK: Events
    
    func richMessageTapped(_ message: MessageType, at indexPath: IndexPath, in chat: ChatViewController) {
        print("tap!")
    }
    
    // MARK: Cells
    
    func cellSizeCalculator(for messagesCollectionViewFlowLayout: MessagesCollectionViewFlowLayout) -> CellSizeCalculator {
        let calculator = TransferMessageSizeCalculator(layout: messagesCollectionViewFlowLayout)
        calculator.font = UIFont.systemFont(ofSize: 24)
        return calculator
    }
    
    func cell(for message: MessageType, isFromCurrentSender: Bool, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> UICollectionViewCell {
        guard case .custom(let raw) = message.kind, let transfer = raw as? RichMessageTransfer else {
            fatalError("ETH service tried to render wrong message kind: \(message.kind)")
        }
        
        guard let cell = messagesCollectionView.dequeueReusableCell(withReuseIdentifier: cellIdentifier, for: indexPath) as? TransferCollectionViewCell else {
            fatalError("Can't dequeue \(cellIdentifier) cell")
        }
        
        cell.currencyLogoImageView.image = EthWalletService.currencyLogo
        cell.currencySymbolLabel.text = EthWalletService.currencySymbol
        
        cell.amountLabel.text = transfer.amount
        cell.dateLabel.text = message.sentDate.humanizedDateTime(withWeekday: false)
        
        cell.isAlignedRight = isFromCurrentSender
        
        return cell
    }
    
    // MARK: Short description
    
    private static var formatter: NumberFormatter = {
        return AdamantBalanceFormat.currencyFormatter(format: .full, currencySymbol: currencySymbol)
    }()
    
    func shortDescription(for transaction: RichMessageTransaction) -> String {
        guard let amount = transaction.richContent?[RichContentKeys.transfer.amount] else {
            return ""
        }
        
        if transaction.isOutgoing {
            return String.localizedStringWithFormat(String.adamantLocalized.chatList.sentMessagePrefix, " ⬅️  \(amount) \(EthWalletService.currencySymbol)")
        } else {
            return "➡️  \(amount) \(EthWalletService.currencySymbol)"
        }
    }
}
