//
//  AdamantApiService.swift
//  Adamant
//
//  Created by Anokhov Pavel on 06.01.2018.
//  Copyright © 2018 Adamant. All rights reserved.
//

import UIKit
import Alamofire

final class AdamantApiService: ApiService {
    // MARK: - Shared constants
    
    struct ApiCommands {
        private init() {}
    }
    
    enum InternalError: Error {
        case endpointBuildFailed
        case signTransactionFailed
        case parsingFailed
        case unknownError
        case noNodesAvailable
        
        func apiServiceErrorWith(error: Error?) -> ApiServiceError {
            return .internalError(message: self.localized, error: error)
        }
        
        var localized: String {
            switch self {
            case .endpointBuildFailed:
                return NSLocalizedString("ApiService.InternalError.EndpointBuildFailed", comment: "Serious internal error: Failed to build endpoint url")
                
            case .signTransactionFailed:
                return NSLocalizedString("ApiService.InternalError.FailedTransactionSigning", comment: "Serious internal error: Failed to sign transaction")
                
            case .parsingFailed:
                return NSLocalizedString("ApiService.InternalError.ParsingFailed", comment: "Serious internal error: Error parsing response")
                
            case .unknownError:
                return String.adamantLocalized.sharedErrors.unknownError
            
            case .noNodesAvailable:
                return NSLocalizedString("ApiService.InternalError.NoNodesAvailable", comment: "Serious internal error: No nodes available")
            }
        }
    }
    
    // MARK: - Dependencies
    
    let adamantCore: AdamantCore
    
    weak var nodesSource: NodesSource? {
        didSet {
            updateCurrentNodes()
        }
    }
    
    // MARK: - Properties
    
    private var _lastRequestTimeDelta: TimeInterval?
    private var semaphore: DispatchSemaphore = DispatchSemaphore(value: 1)
    
    private(set) var currentNodes: [Node] = [] {
        didSet {
            guard oldValue != currentNodes else { return }
            sendCurrentNodeUpdateNotification()
        }
    }
    
    private(set) var lastRequestTimeDelta: TimeInterval? {
        get {
            defer { semaphore.signal() }
            semaphore.wait()
            
            return _lastRequestTimeDelta
        }
        set {
            semaphore.wait()
            _lastRequestTimeDelta = newValue
            semaphore.signal()
        }
    }
    
    var sendingMsgTaskId: UIBackgroundTaskIdentifier = UIBackgroundTaskIdentifier.invalid
    
    let defaultResponseDispatchQueue = DispatchQueue(
        label: "com.adamant.response-queue",
        qos: .userInteractive
    )
    
    private let manager: Session = {
        let configuration = AF.sessionConfiguration
        configuration.waitsForConnectivity = true
        let manager = Alamofire.Session.init(configuration: configuration)
        return manager
    }()
    
    // MARK: - Init
    
    init(adamantCore: AdamantCore) {
        self.adamantCore = adamantCore
        
        NotificationCenter.default.addObserver(
            forName: Notification.Name.NodesSource.nodesUpdate,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.updateCurrentNodes()
        }
    }
    
    // MARK: - Tools
    
    func buildUrl(url: URL, path: String, queryItems: [URLQueryItem]? = nil) throws -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ApiServiceError.internalError(message: "Failed to build URL from \(url)", error: nil)
        }
        
        components.path = path
        components.queryItems = queryItems
        
        return try components.asURL()
    }
    
    func sendRequest<Output: Decodable>(
        path: String,
        queryItems: [URLQueryItem]? = nil,
        method: HTTPMethod = .get,
        waitsForConnectivity: Bool = false,
        completion: @escaping (ApiServiceResult<Output>) -> Void
    ) {
        sendRequest(
            path: path,
            queryItems: queryItems,
            method: method,
            body: Optional<Bool>.none,
            waitsForConnectivity: waitsForConnectivity,
            completion: completion
        )
    }
    
    func sendRequest<Body: Encodable, Output: Decodable>(
        path: String,
        queryItems: [URLQueryItem]? = nil,
        method: HTTPMethod = .get,
        body: Body? = nil,
        waitsForConnectivity: Bool = false,
        completion: @escaping (ApiServiceResult<Output>) -> Void
    ) {
        guard !currentNodes.isEmpty else {
            let error = InternalError.endpointBuildFailed.apiServiceErrorWith(
                error: InternalError.noNodesAvailable
            )
            completion(.failure(error))
            return
        }
        
        var needNodesUpdate = false
        
        sendSafeRequest(
            nodes: currentNodes,
            path: path,
            queryItems: queryItems,
            method: method,
            body: body,
            waitsForConnectivity: waitsForConnectivity,
            onFailure: { node in
                node.connectionStatus = .offline
                needNodesUpdate = true
            },
            completion: { [weak self] in
                completion($0)
                guard needNodesUpdate else { return }
                self?.nodesSource?.nodesUpdate()
            }
        )
        
        updateCurrentNodes()
    }
    
    @discardableResult
    func sendRequest<Output: Decodable>(
        url: URLConvertible,
        method: HTTPMethod = .get,
        waitsForConnectivity: Bool = false,
        completion: @escaping (ApiServiceResult<Output>) -> Void
    ) -> DataRequest {
        sendRequest(
            url: url,
            method: method,
            body: Optional<Bool>.none,
            waitsForConnectivity: waitsForConnectivity,
            completion: completion
        )
    }
    
    private func createRequest(
        url: URLConvertible,
        method: HTTPMethod,
        parameters: Parameters?,
        encoding: ParameterEncoding,
        waitsForConnectivity: Bool,
        headers: HTTPHeaders?
    ) -> DataRequest {
        return manager.request(
            url,
            method: method,
            parameters: parameters,
            encoding: encoding,
            headers: headers
        )
    }
    
    func sendRequest(request: DataRequest) async throws -> Data {
        return try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Data, Error>) in
            request.responseData(queue: defaultResponseDispatchQueue) { response in
                switch response.result {
                case .success(let data):
                    continuation.resume(returning: data)
                    
                case .failure(let error):
                    continuation.resume(throwing: ApiServiceError.init(error: error))
                }
            }
        }
    }
    
    @discardableResult
    func sendRequest<Body: Encodable, Output: Decodable>(
        url: URLConvertible,
        method: HTTPMethod = .get,
        body: Body? = nil,
        waitsForConnectivity: Bool = false,
        completion: @escaping (ApiServiceResult<Output>) -> Void
    ) -> DataRequest {
        let request = createRequest(
            url: url,
            method: method,
            parameters: body?.asDictionary,
            encoding: JSONEncoding.default,
            waitsForConnectivity: waitsForConnectivity,
            headers: HTTPHeaders(["Content-Type": "application/json"])
        )
        
        Task {
            do {
                let data = try await sendRequest(request: request)
                
                do {
                    let model = try JSONDecoder().decode(Output.self, from: data)
                    
                    if let timestampResponse = model as? ServerResponseWithTimestamp {
                        let nodeDate = AdamantUtilities.decodeAdamant(timestamp: timestampResponse.nodeTimestamp)
                        lastRequestTimeDelta = Date().timeIntervalSince(nodeDate)
                    }
                    
                    completion(.success(model))
                } catch {
                    completion(.failure(InternalError.parsingFailed.apiServiceErrorWith(error: error)))
                }
            } catch let error as ApiServiceError {
                completion(.failure(error))
            } catch {
                completion(.failure(.init(error: error)))
            }
        }
        
        return request
    }
    
    func sendRequest<Output: Decodable>(
        url: URLConvertible,
        method: HTTPMethod,
        parameters: Parameters?
    ) async throws -> Output {
        try await sendRequest(
            url: url,
            method: method,
            parameters: parameters,
            encoding: URLEncoding.default
        )
    }
    
    func sendRequest<Output: Decodable>(
        url: URLConvertible,
        method: HTTPMethod,
        parameters: Parameters?,
        encoding: ParameterEncoding
    ) async throws -> Output {
        let data = try await sendRequest(
            url: url,
            method: method,
            parameters: parameters,
            encoding: encoding
        )
        
        do {
            let model = try JSONDecoder().decode(Output.self, from: data)
            return model
        } catch {
            throw InternalError.parsingFailed.apiServiceErrorWith(error: error)
        }
    }
    
    func sendRequest(
        url: URLConvertible,
        method: HTTPMethod,
        parameters: Parameters?
    ) async throws -> Data {
        try await sendRequest(
            url: url,
            method: method,
            parameters: parameters,
            encoding: URLEncoding.default
        )
    }
    
    func sendRequest(
        url: URLConvertible,
        method: HTTPMethod,
        parameters: Parameters?,
        encoding: ParameterEncoding
    ) async throws -> Data {
        return try await sendRequest(
            url: url,
            method: method,
            parameters: parameters,
            encoding: encoding,
            waitsForConnectivity: false
        )
    }
    
    private func sendRequest(
        url: URLConvertible,
        method: HTTPMethod,
        parameters: Parameters?,
        encoding: ParameterEncoding,
        waitsForConnectivity: Bool
    ) async throws -> Data {
        let request = createRequest(
            url: url,
            method: method,
            parameters: parameters,
            encoding: encoding,
            waitsForConnectivity: waitsForConnectivity,
            headers: HTTPHeaders(["Content-Type": "application/json"])
        )
        
        return try await sendRequest(request: request)
    }
    
    static func translateServerError(_ error: String?) -> ApiServiceError {
        guard let error = error else {
            return InternalError.unknownError.apiServiceErrorWith(error: nil)
        }
        
        switch error {
        case "Account not found":
            return .accountNotFound
            
        default:
            return .serverError(error: error)
        }
    }
}

private extension AdamantApiService {
    /// On failure this method doesn't call completion, it just goes to next node. Completion called on success or on last node failure.
    private func sendSafeRequest<Body: Encodable, Output: Decodable>(
        nodes: [Node],
        path: String,
        queryItems: [URLQueryItem]?,
        method: HTTPMethod,
        body: Body?,
        waitsForConnectivity: Bool = false,
        onFailure: @escaping (Node) -> Void,
        completion: @escaping (ApiServiceResult<Output>) -> Void
    ) {
        guard let node = nodes.first else {
            completion(.failure(.networkError(error: InternalError.unknownError)))
            return
        }
        
        let url: URL
        do {
            url = try buildUrl(node: node, path: path, queryItems: queryItems)
        } catch {
            let err = InternalError.endpointBuildFailed.apiServiceErrorWith(error: error)
            completion(.failure(err))
            return
        }
        
        sendRequest(
            url: url,
            method: method,
            body: body,
            waitsForConnectivity: waitsForConnectivity,
            completion: makeSafeRequestCompletion(
                nodes: nodes,
                path: path,
                queryItems: queryItems,
                method: method,
                body: body,
                waitsForConnectivity: waitsForConnectivity,
                onFailure: onFailure,
                completion: completion
            )
        )
    }
    
    private func makeSafeRequestCompletion<Body: Encodable, Output: Decodable>(
        nodes: [Node],
        path: String,
        queryItems: [URLQueryItem]?,
        method: HTTPMethod,
        body: Body?,
        waitsForConnectivity: Bool = false,
        onFailure: @escaping (Node) -> Void,
        completion: @escaping (ApiServiceResult<Output>) -> Void
    ) -> (ApiServiceResult<Output>) -> Void {
        { [weak self] result in
            switch result {
            case .success:
                completion(result)
            case let .failure(error):
                switch error {
                case .networkError:
                    var nodes = nodes
                    onFailure(nodes.removeFirst())
                    self?.sendSafeRequest(
                        nodes: nodes,
                        path: path,
                        queryItems: queryItems,
                        method: method,
                        body: body,
                        waitsForConnectivity: waitsForConnectivity,
                        onFailure: onFailure,
                        completion: completion
                    )
                case .accountNotFound, .internalError, .notLogged, .serverError, .requestCancelled:
                    completion(result)
                }
            }
        }
    }
    
    private func updateCurrentNodes() {
        semaphore.wait()
        currentNodes = nodesSource?.getAllowedNodes(needWS: false) ?? []
        semaphore.signal()
    }
    
    private func sendCurrentNodeUpdateNotification() {
        NotificationCenter.default.post(
            name: Notification.Name.ApiService.currentNodeUpdate,
            object: self,
            userInfo: nil
        )
    }
    
    private func buildUrl(node: Node, path: String, queryItems: [URLQueryItem]? = nil) throws -> URL {
        guard let url = node.asURL() else { throw InternalError.endpointBuildFailed }
        return try buildUrl(url: url, path: path, queryItems: queryItems)
    }
}

private extension ApiServiceError {
    init(error: Error) {
        let afError = error as? AFError
        
        switch afError {
        case .explicitlyCancelled:
            self = .requestCancelled
        default:
            self = .networkError(error: error)
        }
    }
}
