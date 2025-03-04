//
//  ObservableValue.swift
//  Adamant
//
//  Created by Andrey Golubenko on 24.01.2023.
//  Copyright © 2023 Adamant. All rights reserved.
//

import Combine

/// `Published` changes its `wrappedValue` after calling `sink` or `assign`.
/// But `ObservableValue` does it before.
@propertyWrapper final class ObservableValue<Output>: Publisher {
    typealias Output = Output
    typealias Failure = Never
    
    private let subject: CurrentValueSubject<Output, Failure>

    var wrappedValue: Output {
        get { subject.value }
        set { subject.value = newValue }
    }
    
    var projectedValue: some Observable<Output> {
        subject
    }
    
    func receive<S>(
        subscriber: S
    ) where S: Subscriber, Never == S.Failure, Output == S.Input {
        subject.receive(subscriber: subscriber)
    }

    init(wrappedValue: Output) {
        subject = .init(wrappedValue)
    }
}

extension Publisher where Failure == Never {
    func assign(to observableValue: ObservableValue<Output>) -> AnyCancellable {
        assign(to: \.wrappedValue, on: observableValue)
    }
}
