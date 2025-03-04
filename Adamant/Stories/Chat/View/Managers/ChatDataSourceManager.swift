//
//  ChatDataSourceManager.swift
//  Adamant
//
//  Created by Andrey Golubenko on 23.12.2022.
//  Copyright © 2022 Adamant. All rights reserved.
//

import MessageKit
import UIKit
import Combine

@MainActor
final class ChatDataSourceManager: MessagesDataSource {
    private let viewModel: ChatViewModel
    
    var currentSender: SenderType {
        viewModel.sender
    }
    
    init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }
    
    func numberOfSections(in messagesCollectionView: MessagesCollectionView) -> Int {
        viewModel.messages.count
    }
    
    func messageForItem(
        at indexPath: IndexPath,
        in messagesCollectionView: MessagesCollectionView
    ) -> MessageType {
        viewModel.messages[indexPath.section]
    }
    
    func messageTopLabelAttributedText(
        for message: MessageType,
        at _: IndexPath
    ) -> NSAttributedString? {
        guard message.fullModel.status == .failed else { return nil }
        
        return .init(
            string: .adamantLocalized.chat.failToSend,
            attributes: [
                .font: UIFont.boldSystemFont(ofSize: 10),
                .foregroundColor: UIColor.adamant.primary
            ]
        )
    }
    
    func messageBottomLabelAttributedText(
        for message: MessageType,
        at _: IndexPath
    ) -> NSAttributedString? {
        message.fullModel.bottomString?.string
    }
    
    func cellTopLabelAttributedText(
        for message: MessageType,
        at indexPath: IndexPath
    ) -> NSAttributedString? {
        message.fullModel.dateHeader?.string
    }
    
    func customCell(
        for message: MessageType,
        at indexPath: IndexPath,
        in messagesCollectionView: MessagesCollectionView
    ) -> UICollectionViewCell {
        let cell = messagesCollectionView.dequeueReusableCell(
            ChatViewController.TransactionCell.self,
            for: indexPath
        )
        
        let publisher: any Observable<ChatTransactionContainerView.Model> = viewModel.$messages.compactMap {
            let message = $0[safe: indexPath.section]
            guard case let .transaction(model) = message?.fullModel.content else { return nil }
            return model.value
        }
        
        cell.wrappedView.actionHandler = { [weak self] in self?.handleAction($0) }
        cell.wrappedView.setSubscription(publisher: publisher)
        return cell
    }
}

private extension ChatDataSourceManager {
    func handleAction(_ action: ChatAction) {
        switch action {
        case let .openTransactionDetails(id):
            viewModel.didTapTransfer.send(id)
        case let .forceUpdateTransactionStatus(id):
            viewModel.forceUpdateTransactionStatus(id: id)
        }
    }
}
