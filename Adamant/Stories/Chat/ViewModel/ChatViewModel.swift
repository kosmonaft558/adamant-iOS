//
//  ChatViewModel.swift
//  Adamant
//
//  Created by Andrey Golubenko on 23.12.2022.
//  Copyright © 2022 Adamant. All rights reserved.
//

import Combine
import CoreData
import MarkdownKit

final class ChatViewModel: NSObject {
    // MARK: Dependencies
    
    private let chatsProvider: ChatsProvider
    private let markdownParser: MarkdownParser
    private let transfersProvider: TransfersProvider
    private let chatMessageFactory: ChatMessageFactory
    private let addressBookService: AddressBookService
    private let visibleWalletService: VisibleWalletsService
    private let accountService: AccountService
    private let accountProvider: AccountsProvider
    private let richMessageProviders: [String: RichMessageProvider]
    private lazy var chatMessagesListFactory = makeChatMessagesListFactory()
    
    // MARK: Properties
    
    private weak var preservationDelegate: ChatPreservationDelegate?
    private var controller: NSFetchedResultsController<ChatTransaction>?
    private var subscriptions = Set<AnyCancellable>()
    private var timerSubscription: AnyCancellable?
    private var messageIdToShow: String?
    private var isLoading = false
    
    private(set) var chatroom: Chatroom?
    private(set) var chatTransactions: [ChatTransaction] = []
    
    let didTapTransfer = ObservableSender<String>()
    let dialog = ObservableSender<ChatDialog>()
    let didTapAdmChat = ObservableSender<(Chatroom, String?)>()
    let didTapAdmSend = ObservableSender<AdamantAddress>()
    
    private let _closeScreen = ObservableSender<Void>()
    var closeScreen: some Observable<Void> { _closeScreen }
    
    @ObservableValue private(set) var fullscreenLoading = false
    @ObservableValue private(set) var sender = ChatSender.default
    @ObservableValue private(set) var messages = [ChatMessage]()
    @ObservableValue private(set) var isAttachmentButtonAvailable = false
    @ObservableValue private(set) var isSendingAvailable = false
    @ObservableValue private(set) var fee = ""
    @ObservableValue private(set) var partnerName: String?
    @ObservableValue var inputText = ""
    
    var startPosition: ChatStartPosition? {
        if let messageIdToShow = messageIdToShow {
            return .messageId(messageIdToShow)
        }
        
        guard let address = chatroom?.partner?.address else { return nil }
        return chatsProvider.chatPositon[address].map { .offset(.init($0)) }
    }
    
    var freeTokensURL: URL? {
        guard let address = chatroom?.partner?.address else { return nil }
        let urlString: String = .adamantLocalized.wallets.getFreeTokensUrl(for: address)
        
        guard let url = URL(string: urlString) else {
            dialog.send(.error("Failed to create URL with string: \(urlString)"))
            return nil
        }
        
        return url
    }
    
    init(
        chatsProvider: ChatsProvider,
        markdownParser: MarkdownParser,
        transfersProvider: TransfersProvider,
        chatMessageFactory: ChatMessageFactory,
        addressBookService: AddressBookService,
        visibleWalletService: VisibleWalletsService,
        accountService: AccountService,
        accountProvider: AccountsProvider,
        richMessageProviders: [String: RichMessageProvider]
    ) {
        self.chatsProvider = chatsProvider
        self.markdownParser = markdownParser
        self.transfersProvider = transfersProvider
        self.chatMessageFactory = chatMessageFactory
        self.addressBookService = addressBookService
        self.richMessageProviders = richMessageProviders
        self.visibleWalletService = visibleWalletService
        self.accountService = accountService
        self.accountProvider = accountProvider
        super.init()
        setupObservers()
    }
    
    func setup(
        account: AdamantAccount?,
        chatroom: Chatroom,
        messageToShow: MessageTransaction?,
        preservationDelegate: ChatPreservationDelegate?
    ) {
        reset()
        self.chatroom = chatroom
        self.preservationDelegate = preservationDelegate
        controller = chatsProvider.getChatController(for: chatroom)
        controller?.delegate = self
        isSendingAvailable = !chatroom.isReadonly
        messageIdToShow = messageToShow?.chatMessageId
        updateTitle()
        updateAttachmentButtonAvailability()
        
        if let account = account {
            sender = .init(senderId: account.address, displayName: account.address)
        }
        
        if let partnerAddress = chatroom.partner?.address {
            preservationDelegate?.getPreservedMessageFor(
                address: partnerAddress,
                thenRemoveIt: true
            ).map { inputText = $0 }
        }
    }
    
    func loadFirstMessagesIfNeeded() {
        guard let address = chatroom?.partner?.address else { return }
        
        if address == AdamantContacts.adamantWelcomeWallet.name || chatsProvider.isChatLoaded[address] == true {
            updateTransactions(performFetch: true)
        } else {
            loadMessages(address: address, offset: .zero, fullscreenLoading: true)
        }
    }
    
    func loadMoreMessagesIfNeeded() {
        guard
            let address = chatroom?.partner?.address,
            isNeedToLoadMoreMessages
        else { return }
        
        let offset = chatsProvider.chatLoadedMessages[address] ?? .zero
        loadMessages(address: address, offset: offset, fullscreenLoading: false)
    }
    
    func sendMessage(text: String) {
        let message: AdamantMessage = markdownParser.parse(text).length == text.count
            ? .text(text)
            : .markdownText(text)
        
        guard
            let partnerAddress = chatroom?.partner?.address,
            validateSendingMessage(message: message)
        else { return }
        
        chatsProvider.sendMessage(
            message,
            recipientId: partnerAddress,
            from: chatroom
        ) { [weak self] result in
            DispatchQueue.onMainAsync {
                self?.handleMessageSendingResult(result: result, sentText: text)
            }
        }
    }
    
    func loadTransactionStatusIfNeeded(id: String, forceUpdate: Bool) {
        guard
            let transaction = chatTransactions.first(where: { $0.chatMessageId == id }),
            let richMessageTransaction = transaction as? RichMessageTransaction,
            richMessageTransaction.transactionStatus?.isFinal != true || forceUpdate
        else { return }
        
        if forceUpdate,
           let index = messages.firstIndex(where: { id == $0.id }),
           case var .transaction(model) = messages[index].content {
            model.status = .notInitiated
            messages[index].content = .transaction(model)
        }
        
        chatsProvider.updateStatus(for: richMessageTransaction, resetBeforeUpdate: forceUpdate)
    }
    
    func preserveMessage(_ message: String) {
        guard let partnerAddress = chatroom?.partner?.address else { return }
        preservationDelegate?.preserveMessage(message, forAddress: partnerAddress)
    }
    
    func blockChat() {
        guard let address = chatroom?.partner?.address else {
            return assertionFailure("Can't block user without address")
        }
        
        chatroom?.isHidden = true
        try? chatroom?.managedObjectContext?.save()
        chatsProvider.blockChat(with: address)
        _closeScreen.send()
    }
    
    func setNewName(_ newName: String) {
        guard let address = chatroom?.partner?.address else {
            return assertionFailure("Can't set name without address")
        }
        
        addressBookService.set(name: newName, for: address)
        updateTitle()
    }
    
    func saveChatOffset(_ offset: CGFloat?) {
        guard let address = chatroom?.partner?.address else { return }
        chatsProvider.chatPositon[address] = offset.map { .init($0) }
    }
    
    func entireChatWasRead() {
        guard
            let chatroom = chatroom,
            chatroom.hasUnreadMessages || chatroom.lastTransaction?.isUnread == true
        else { return }
        
        chatsProvider.markChatAsRead(chatroom: chatroom)
    }
    
    func hideMessage(id: String) {
        guard let transaction = chatTransactions.first(where: { $0.chatMessageId == id })
        else { return }
        
        transaction.isHidden = true
        try? transaction.managedObjectContext?.save()
        
        chatroom?.updateLastTransaction()
        transaction.transactionId.map { chatsProvider.removeMessage(with: $0) }
    }
    
    func didSelectURL(_ url: URL) {
        if url.scheme == "adm" {
            guard let adm = url.absoluteString.getLegacyAdamantAddress(),
                  let partnerAddress = chatroom?.partner?.address
            else {
                return
            }
            
            dialog.send(.admMenu(adm, partnerAddress: partnerAddress))
            return
        }
        
        dialog.send(.url(url))
    }
    
    func process(adm: AdamantAddress, action: AddressChatShareType) {
        if action == .send {
            didTapAdmSend.send(adm)
            return
        }
        
        guard let room = self.chatsProvider.getChatroom(for: adm.address) else {
            self.findAccount(with: adm.address, name: adm.name, message: adm.message)
            return
        }
        
        self.startNewChat(with: room, name: adm.name, message: adm.message)
    }
    
    func cancelMessage(id: String) {
        guard let transaction = chatTransactions.first(where: { $0.chatMessageId == id })
        else { return }
        
        chatsProvider.cancelMessage(transaction) { [dialog] result in
            switch result {
            case let .failure(error):
                dialog.send(.richError(error))
            case .invalidTransactionStatus:
                dialog.send(.warning(.adamantLocalized.chat.cancelError))
            case .success:
                break
            }
        }
    }
    
    func retrySendMessage(id: String) {
        guard let transaction = chatTransactions.first(where: { $0.chatMessageId == id })
        else { return }
        
        chatsProvider.retrySendMessage(transaction) { [dialog] result in
            switch result {
            case let .failure(error):
                dialog.send(.richError(error))
            case .success, .invalidTransactionStatus:
                break
            }
        }
    }
}

extension ChatViewModel: NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_: NSFetchedResultsController<NSFetchRequestResult>) {
        updateTransactions(performFetch: false)
    }
}

private extension ChatViewModel {
    var isNeedToLoadMoreMessages: Bool {
        guard let address = chatroom?.partner?.address else { return false }

        return chatsProvider.chatLoadedMessages[address] ?? .zero < chatsProvider.chatMaxMessages[address] ?? .zero
    }
    
    func setupObservers() {
        $inputText
            .removeDuplicates()
            .sink { [weak self] _ in self?.inputTextUpdated() }
            .store(in: &subscriptions)
        
        NotificationCenter.default
            .publisher(for: .AdamantVisibleWalletsService.visibleWallets)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateAttachmentButtonAvailability() }
            .store(in: &subscriptions)
    }
    
    func loadMessages(address: String, offset: Int, fullscreenLoading: Bool) {
        guard !isLoading else { return }

        isLoading = true
        self.fullscreenLoading = fullscreenLoading
        chatsProvider.getChatMessages(
            with: address,
            offset: offset
        ) { [weak self] in
            DispatchQueue.onMainAsync {
                self?.updateTransactions(performFetch: true)
            }
        }
    }
    
    func updateTransactions(performFetch: Bool) {
        if performFetch {
            try? controller?.performFetch()
        }
        
        chatTransactions = controller?.fetchedObjects ?? []
        updateMessages(resetLoadingProperty: true)
    }
    
    func updateMessages(resetLoadingProperty: Bool) {
        timerSubscription = nil
        
        Task(priority: .userInitiated) { [chatTransactions, sender, isNeedToLoadMoreMessages] in
            var expirationTimestamp: TimeInterval?
            
            let messages = await chatMessagesListFactory.makeMessages(
                transactions: chatTransactions,
                sender: sender,
                isNeedToLoadMoreMessages: isNeedToLoadMoreMessages,
                expirationTimestamp: &expirationTimestamp
            )
            
            await setupNewMessages(
                newMessages: messages,
                resetLoadingProperty: resetLoadingProperty,
                expirationTimestamp: expirationTimestamp
            )
        }
    }
    
    @MainActor func setupNewMessages(
        newMessages: [ChatMessage],
        resetLoadingProperty: Bool,
        expirationTimestamp: TimeInterval?
    ) async {
        messages = newMessages
        fullscreenLoading = false
        
        if resetLoadingProperty {
            isLoading = false
        }
        
        guard let expirationTimestamp = expirationTimestamp else { return }
        setupMessagesUpdateTimer(expirationTimestamp: expirationTimestamp)
    }
    
    func setupMessagesUpdateTimer(expirationTimestamp: TimeInterval) {
        let currentTimestamp = Date().timeIntervalSince1970
        guard currentTimestamp < expirationTimestamp else { return }
        let interval = expirationTimestamp - currentTimestamp
        
        timerSubscription = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.updateMessages(resetLoadingProperty: false) }
    }
    
    func reset() {
        sender = .default
        chatTransactions = []
        messages = []
        fullscreenLoading = false
        isLoading = false
        inputText = ""
        isAttachmentButtonAvailable = false
        isSendingAvailable = false
        fee = ""
        partnerName = nil
        messageIdToShow = nil
        controller = nil
        chatroom = nil
        preservationDelegate = nil
    }
    
    func validateSendingMessage(message: AdamantMessage) -> Bool {
        let validationStatus = chatsProvider.validateMessage(message)
        
        switch validationStatus {
        case .isValid:
            return true
        case .empty:
            return false
        case .tooLong:
            dialog.send(.toast(validationStatus.localized))
            return false
        }
    }
    
    func handleMessageSendingResult(result: ChatsProviderResultWithTransaction, sentText: String) {
        switch result {
        case .success:
            break
        case let .failure(error):
            switch error {
            case .messageNotValid:
                inputText = sentText
            case .notEnoughMoneyToSend:
                inputText = sentText
                guard transfersProvider.hasTransactions else {
                    dialog.send(.freeTokenAlert)
                    return
                }
            case .accountNotFound, .accountNotInitiated, .dependencyError, .internalError, .networkError, .notLogged, .requestCancelled, .serverError, .transactionNotFound:
                break
            }
            
            dialog.send(.richError(error))
        }
    }
    
    func inputTextUpdated() {
        guard !inputText.isEmpty else {
            fee = ""
            return
        }
        
        let feeString = AdamantBalanceFormat.full.format(
            AdamantMessage.text(inputText).fee,
            withCurrencySymbol: AdmWalletService.currencySymbol
        )
        
        fee = "~\(feeString)"
    }
    
    func updateTitle() {
        partnerName = chatroom?.getName(addressBookService: addressBookService)
    }
    
    func updateAttachmentButtonAvailability() {
        let isAnyWalletVisible = accountService.wallets
            .map { visibleWalletService.isInvisible($0) }
            .contains(false)
        
        isAttachmentButtonAvailable = isAnyWalletVisible
    }
    
    func findAccount(with address: String, name: String?, message: String?) {
        dialog.send(.progress(true))
        accountProvider.getAccount(byAddress: address) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let account):
                DispatchQueue.main.async {
                    self.dialog.send(.progress(false))
                    guard let chatroom = account.chatroom else { return }
                    self.setNameIfNeeded(for: account, chatroom: account.chatroom, name: name)
                    account.chatroom?.isForcedVisible = true
                    self.startNewChat(with: chatroom, message: message)
                }
            case .dummy:
                self.dialog.send(.progress(false))
                self.dialog.send(.dummy(address))
            case .notFound, .invalidAddress, .notInitiated, .networkError:
                self.dialog.send(.progress(false))
                self.dialog.send(.alert(result.localized))
            case .serverError(let error):
                self.dialog.send(.progress(false))
                if let apiError = error as? ApiServiceError, case .internalError(let message, _) = apiError, message == String.adamantLocalized.sharedErrors.unknownError {
                    self.dialog.send(.alert(AccountsProviderResult.notFound(address: address).localized))
                    return
                }
                
                self.dialog.send(.error(result.localized))
            }
        }
    }
    
    func setNameIfNeeded(for account: CoreDataAccount?, chatroom: Chatroom?, name: String?) {
        guard let name = name,
              let account = account,
              account.name == nil
        else {
            return
        }
        account.name = name
        if let chatroom = chatroom, chatroom.title == nil {
            chatroom.title = name
        }
    }
    
    func startNewChat(with chatroom: Chatroom, name: String? = nil, message: String? = nil) {
        setNameIfNeeded(for: chatroom.partner, chatroom: chatroom, name: name)
        didTapAdmChat.send((chatroom, message))
    }
    
    func makeChatMessagesListFactory() -> ChatMessagesListFactory {
        .init(
            chatMessageFactory: chatMessageFactory,
            didTapTransfer: { [didTapTransfer] in didTapTransfer.send($0) },
            forceUpdateStatusAction: { [weak self] in
                self?.loadTransactionStatusIfNeeded(id: $0, forceUpdate: true)
            }
        )
    }
}
