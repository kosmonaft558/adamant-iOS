//
//  BtcTransactionsViewController.swift
//  Adamant
//
//  Created by Anton Boyarkin on 30/01/2019.
//  Copyright © 2019 Adamant. All rights reserved.
//

import UIKit
import BitcoinKit

class BtcTransactionsViewController: TransactionsListViewControllerBase {
    
    // MARK: - Dependencies
    var btcWalletService: BtcWalletService!
    var dialogService: DialogService!
    var router: Router!
    var addressBook: AddressBookService!
    
    // MARK: - Properties
    var transactions: [BtcTransaction] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.refreshControl.beginRefreshing()
        
        currencySymbol = BtcWalletService.currencySymbol
        
        handleRefresh()
    }
    
    override func handleRefresh() {
        transactions.removeAll()
        tableView.reloadData()
        loadData(false)
    }
    
    override func loadData(_ silent: Bool) {
        isBusy = true
        
        Task { @MainActor in
            do {
                let trs = try await btcWalletService.getTransactions(fromTx: transactions.last?.txId)
                transactions.append(contentsOf: trs)
                isNeedToLoadMoore = trs.count > 0
            } catch {
                isNeedToLoadMoore = false
                if !silent {
                    dialogService.showRichError(error: error)
                }
            }
            
            isBusy = false
            tableView.reloadData()
            emptyLabel.isHidden = transactions.count > 0
            stopBottomIndicator()
            refreshControl.endRefreshing()
        }.stored(in: taskManager)
    }
    
    // MARK: - UITableView
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return transactions.count
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let transaction = transactions[indexPath.row]
        
        guard let controller = router.get(scene: AdamantScene.Wallets.Bitcoin.transactionDetails) as? BtcTransactionDetailsViewController else {
            return
        }

        controller.transaction = transaction
        controller.service = btcWalletService

        if let address = btcWalletService.wallet?.address {
            if transaction.senderAddress.caseInsensitiveCompare(address) == .orderedSame {
                controller.senderName = String.adamantLocalized.transactionDetails.yourAddress
            }
            if transaction.recipientAddress.caseInsensitiveCompare(address) == .orderedSame {
                controller.recipientName = String.adamantLocalized.transactionDetails.yourAddress
            }
        }

        navigationController?.pushViewController(controller, animated: true)
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifierCompact, for: indexPath) as? TransactionTableViewCell else {
            // TODO: Display & Log error
            return UITableViewCell(style: .default, reuseIdentifier: "cell")
        }
        
        let transaction = transactions[indexPath.row]
        
        cell.accessoryType = .disclosureIndicator
        
        configureCell(cell, for: transaction)
        return cell
    }
    
    func configureCell(_ cell: TransactionTableViewCell, for transaction: BtcTransaction) {
        let outgoing = transaction.isOutgoing
        let partnerId = outgoing ? transaction.recipientAddress : transaction.senderAddress
   
        var partnerName: String?
        if let address = btcWalletService.wallet?.address {
            if partnerId == address {
                partnerName = String.adamantLocalized.transactionDetails.yourAddress
            } else {
                partnerName = addressBook.getName(for: address)
            }
        }
        
        configureCell(cell,
                      isOutgoing: outgoing,
                      partnerId: partnerId,
                      partnerName: partnerName,
                      amount: transaction.amountValue ?? 0,
                      date: transaction.dateValue)
    }
}
