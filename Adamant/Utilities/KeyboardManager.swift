//
//  KeyboardManager.swift
//  InputBarAccessoryView
//
//  Copyright © 2017-2018 Nathan Tannar.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//
//  Created by Nathan Tannar on 8/18/17.
//

import UIKit

/// An object that observes keyboard notifications such that event callbacks can be set for each notification
open class KeyboardManager: NSObject, UIGestureRecognizerDelegate {
    
    /// A callback that passes a `KeyboardNotification` as an input
    public typealias EventCallback = (KeyboardNotification) -> Void
    
    // MARK: - Properties [Public]
    
    /// A weak reference to a view bounded to the top of the keyboard to act as an `InputAccessoryView`
    /// but kept within the bounds of the `UIViewController`s view
    open weak var inputAccessoryView: UIView?
    
    /// A flag that indicates if a portion of the keyboard is visible on the screen
    private(set) public var isKeyboardHidden: Bool = true
    
    // MARK: - Properties [Private]
    
    /// The `NSLayoutConstraintSet` that holds the `inputAccessoryView` to the bottom if its superview
    private var constraints: NSLayoutConstraintSet?
    
    /// A weak reference to a `UIScrollView` that has been attached for interactive keyboard dismissal
    private weak var scrollView: UIScrollView?
    
    /// The `EventCallback` actions for each `KeyboardEvent`. Default value is EMPTY
    private var callbacks: [KeyboardEvent: EventCallback] = [:]
    
    /// The pan gesture that handles dragging on the `scrollView`
    private var panGesture: UIPanGestureRecognizer?
    
    /// A cached notification used as a starting point when a user dragging the `scrollView` down
    /// to interactively dismiss the keyboard
    private var cachedNotification: KeyboardNotification?
    
    // MARK: - Initialization
    
    /// Creates a `KeyboardManager` object an binds the view as fake `InputAccessoryView`
    ///
    /// - Parameter inputAccessoryView: The view to bind to the top of the keyboard but within its superview
    public convenience init(inputAccessoryView: UIView) {
        self.init()
        self.bind(inputAccessoryView: inputAccessoryView)
    }
    
    /// Creates a `KeyboardManager` object that observes the state of the keyboard
    public override init() {
        super.init()
        addObservers()
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - De-Initialization
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Keyboard Observer
    
    /// Add an observer for each keyboard notification
    private func addObservers() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillShow(notification:)),
                                               name: UIResponder.keyboardWillShowNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardDidShow(notification:)),
                                               name: UIResponder.keyboardDidShowNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillHide(notification:)),
                                               name: UIResponder.keyboardWillHideNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardDidHide(notification:)),
                                               name: UIResponder.keyboardDidHideNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillChangeFrame(notification:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardDidChangeFrame(notification:)),
                                               name: UIResponder.keyboardDidChangeFrameNotification,
                                               object: nil)
    }
    
    // MARK: - Mutate Callback Dictionary
    
    /// Sets the `EventCallback` for a `KeyboardEvent`
    ///
    /// - Parameters:
    ///   - event: KeyboardEvent
    ///   - callback: EventCallback
    /// - Returns: Self
    @discardableResult
    open func on(event: KeyboardEvent, do callback: EventCallback?) -> Self {
        callbacks[event] = callback
        return self
    }
    
    /// Constrains the `inputAccessoryView` to the bottom of its superview and sets the
    /// `.willChangeFrame` and `.willHide` event callbacks such that it mimics an `InputAccessoryView`
    /// that is bound to the top of the keyboard
    ///
    /// - Parameter inputAccessoryView: The view to bind to the top of the keyboard but within its superview
    /// - Returns: Self
    @discardableResult
    open func bind(inputAccessoryView: UIView, usingTabBar tabBar: UITabBar? = nil) -> Self {
        guard let superview = inputAccessoryView.superview else {
            fatalError("`inputAccessoryView` must have a superview")
        }
        let tabBarHeight = isMacOS ? 0 : tabBar?.bounds.size.height ?? 0
        self.inputAccessoryView = inputAccessoryView
        inputAccessoryView.translatesAutoresizingMaskIntoConstraints = false
        constraints = NSLayoutConstraintSet(
            bottom: inputAccessoryView.bottomAnchor.constraint(equalTo: superview.bottomAnchor),
            left: inputAccessoryView.leftAnchor.constraint(equalTo: superview.leftAnchor),
            right: inputAccessoryView.rightAnchor.constraint(equalTo: superview.rightAnchor)
            ).activate()
        
        callbacks[.willShow] = { [weak self] (notification) in
            let keyboardHeight = notification.endFrame.height
            guard
                self?.isKeyboardHidden == false,
                self?.constraints?.bottom?.constant == 0,
                notification.isForCurrentApp else { return }
            self?.animateAlongside(notification) {
                self?.constraints?.bottom?.constant = -keyboardHeight + tabBarHeight
                self?.inputAccessoryView?.superview?.layoutIfNeeded()
            }
        }
        callbacks[.willChangeFrame] = { [weak self] (notification) in
            let keyboardHeight = notification.endFrame.height
            guard
                self?.isKeyboardHidden == false,
                notification.isForCurrentApp else { return }
            self?.animateAlongside(notification) {
                self?.constraints?.bottom?.constant = -keyboardHeight + tabBarHeight
                self?.inputAccessoryView?.superview?.layoutIfNeeded()
            }
        }
        callbacks[.willHide] = { [weak self] (notification) in
            guard notification.isForCurrentApp else { return }
            self?.animateAlongside(notification) { [weak self] in
                self?.constraints?.bottom?.constant = 0
                self?.inputAccessoryView?.superview?.layoutIfNeeded()
            }
        }
        return self
    }
    
    /// Adds a `UIPanGestureRecognizer` to the `scrollView` to enable interactive dismissal`
    ///
    /// - Parameter scrollView: UIScrollView
    /// - Returns: Self
    @discardableResult
    open func bind(to scrollView: UIScrollView) -> Self {
        self.scrollView = scrollView
        self.scrollView?.keyboardDismissMode = .interactive // allows dismissing keyboard interactively
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePanGestureRecognizer))
        recognizer.delegate = self
        self.panGesture = recognizer
        self.scrollView?.addGestureRecognizer(recognizer)
        return self
    }
    
    // MARK: - Keyboard Notifications
    
    /// An observer method called last in the lifecycle of a keyboard becoming visible
    ///
    /// - Parameter notification: NSNotification
    @objc
    open func keyboardDidShow(notification: NSNotification) {
        guard let keyboardNotification = KeyboardNotification(from: notification) else { return }
        callbacks[.didShow]?(keyboardNotification)
    }
    
    /// An observer method called last in the lifecycle of a keyboard becoming hidden
    ///
    /// - Parameter notification: NSNotification
    @objc
    open func keyboardDidHide(notification: NSNotification) {
        isKeyboardHidden = true
        guard let keyboardNotification = KeyboardNotification(from: notification) else { return }
        callbacks[.didHide]?(keyboardNotification)
    }
    
    /// An observer method called third in the lifecycle of a keyboard becoming visible/hidden
    ///
    /// - Parameter notification: NSNotification
    @objc
    open func keyboardDidChangeFrame(notification: NSNotification) {
        guard let keyboardNotification = KeyboardNotification(from: notification) else { return }
        callbacks[.didChangeFrame]?(keyboardNotification)
        cachedNotification = keyboardNotification
    }
    
    /// An observer method called first in the lifecycle of a keyboard becoming visible/hidden
    ///
    /// - Parameter notification: NSNotification
    @objc
    open func keyboardWillChangeFrame(notification: NSNotification) {
        guard let keyboardNotification = KeyboardNotification(from: notification) else { return }
        callbacks[.willChangeFrame]?(keyboardNotification)
        cachedNotification = keyboardNotification
    }
    
    /// An observer method called second in the lifecycle of a keyboard becoming visible
    ///
    /// - Parameter notification: NSNotification
    @objc
    open func keyboardWillShow(notification: NSNotification) {
        isKeyboardHidden = false
        guard let keyboardNotification = KeyboardNotification(from: notification) else { return }
        callbacks[.willShow]?(keyboardNotification)
    }
    
    /// An observer method called second in the lifecycle of a keyboard becoming hidden
    ///
    /// - Parameter notification: NSNotification
    @objc
    open func keyboardWillHide(notification: NSNotification) {
        guard let keyboardNotification = KeyboardNotification(from: notification) else { return }
        callbacks[.willHide]?(keyboardNotification)
    }
    
    // MARK: - Helper Methods
    
    private func animateAlongside(_ notification: KeyboardNotification, animations: @escaping () -> Void) {
        UIView.animate(withDuration: notification.timeInterval, delay: 0, options: [notification.animationOptions, .allowAnimatedContent, .beginFromCurrentState], animations: animations, completion: nil)
    }
    
    // MARK: - UIGestureRecognizerDelegate
    
    /// Starts with the cached `KeyboardNotification` and calculates a new `endFrame` based
    /// on the `UIPanGestureRecognizer` then calls the `.willChangeFrame` `EventCallback` action
    ///
    /// - Parameter recognizer: UIPanGestureRecognizer
    @objc
    open func handlePanGestureRecognizer(recognizer: UIPanGestureRecognizer) {
        guard
            !isKeyboardHidden,
            var keyboardNotification = cachedNotification,
            case .changed = recognizer.state,
            let view = recognizer.view,
            let window = UIApplication.shared.windows.first
            else { return }
        
        let location = recognizer.location(in: view)
        let absoluteLocation = view.convert(location, to: window)
        var frame = keyboardNotification.endFrame
        frame.origin.y = max(absoluteLocation.y, window.bounds.height - frame.height)
        frame.size.height = window.bounds.height - frame.origin.y
        keyboardNotification.endFrame = frame
        callbacks[.willChangeFrame]?(keyboardNotification)
    }
    
    /// Only receive a `UITouch` event when the `scrollView`'s keyboard dismiss mode is interactive
    open func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        return scrollView?.keyboardDismissMode == .interactive
    }
    
    /// Only recognice simultaneous gestures when its the `panGesture`
    open func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return gestureRecognizer === panGesture
    }
    
}

//
//  KeyboardEvent.swift
//  InputBarAccessoryView
//
//  Copyright © 2017-2018 Nathan Tannar.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//
//  Created by Nathan Tannar on 8/18/17.
//
import Foundation

/// Keyboard events that can happen. Translates directly to `UIKeyboard` notifications from UIKit.
public enum KeyboardEvent {
    
    /// Event raised by UIKit's `.UIKeyboardWillShow`.
    case willShow
    
    /// Event raised by UIKit's `.UIKeyboardDidShow`.
    case didShow
    
    /// Event raised by UIKit's `.UIKeyboardWillShow`.
    case willHide
    
    /// Event raised by UIKit's `.UIKeyboardDidHide`.
    case didHide
    
    /// Event raised by UIKit's `.UIKeyboardWillChangeFrame`.
    case willChangeFrame
    
    /// Event raised by UIKit's `.UIKeyboardDidChangeFrame`.
    case didChangeFrame
    
    /// Non-keyboard based event raised by UIKit
    case unknown
    
}

//
//  KeyboardNotification.swift
//  InputBarAccessoryView
//
//  Copyright © 2017-2018 Nathan Tannar.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//
//  Created by Nathan Tannar on 8/18/17.
//

import UIKit

/// An object containing the key animation properties from NSNotification
public struct KeyboardNotification {
    
    // MARK: - Properties
    
    /// The event that triggered the transition
    public let event: KeyboardEvent
    
    /// The animation length the keyboards transition
    public let timeInterval: TimeInterval
    
    /// The animation properties of the keyboards transition
    public let animationOptions: UIView.AnimationOptions
    
    /// iPad supports split-screen apps, this indicates if the notification was for the current app
    public let isForCurrentApp: Bool
    
    /// The keyboards frame at the start of its transition
    public var startFrame: CGRect
    
    /// The keyboards frame at the beginning of its transition
    public var endFrame: CGRect
    
    /// Requires that the `NSNotification` is based on a `UIKeyboard...` event
    ///
    /// - Parameter notification: `KeyboardNotification`
    public init?(from notification: NSNotification) {
        guard notification.event != .unknown else { return nil }
        self.event = notification.event
        self.timeInterval = notification.timeInterval ?? 0.25
        self.animationOptions = notification.animationOptions
        self.isForCurrentApp = notification.isForCurrentApp ?? true
        self.startFrame = notification.startFrame ?? .zero
        self.endFrame = notification.endFrame ?? .zero
    }
    
}

//
//  NSConstraintLayoutSet.swift
//  InputBarAccessoryView
//
//  Copyright © 2017-2018 Nathan Tannar.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//
//  Created by Nathan Tannar on 8/25/17.
//

import Foundation
import UIKit

class NSLayoutConstraintSet {
    
    var top: NSLayoutConstraint?
    var bottom: NSLayoutConstraint?
    var left: NSLayoutConstraint?
    var right: NSLayoutConstraint?
    var centerX: NSLayoutConstraint?
    var centerY: NSLayoutConstraint?
    var width: NSLayoutConstraint?
    var height: NSLayoutConstraint?
    
    public init(top: NSLayoutConstraint? = nil, bottom: NSLayoutConstraint? = nil,
                left: NSLayoutConstraint? = nil, right: NSLayoutConstraint? = nil,
                centerX: NSLayoutConstraint? = nil, centerY: NSLayoutConstraint? = nil,
                width: NSLayoutConstraint? = nil, height: NSLayoutConstraint? = nil) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
        self.centerX = centerX
        self.centerY = centerY
        self.width = width
        self.height = height
    }
    
    /// All of the currently configured constraints
    private var availableConstraints: [NSLayoutConstraint] {
        #if swift(>=4.1)
        return [top, bottom, left, right, centerX, centerY, width, height].compactMap {$0}
        #else
        return [top, bottom, left, right, centerX, centerY, width, height].flatMap {$0}
        #endif
    }
    
    /// Activates all of the non-nil constraints
    ///
    /// - Returns: Self
    @discardableResult
    func activate() -> Self {
        NSLayoutConstraint.activate(availableConstraints)
        return self
    }
    
    /// Deactivates all of the non-nil constraints
    ///
    /// - Returns: Self
    @discardableResult
    func deactivate() -> Self {
        NSLayoutConstraint.deactivate(availableConstraints)
        return self
    }
}

//
//  NSNotification+Extensions.swift
//  InputBarAccessoryView
//
//  Copyright © 2017-2018 Nathan Tannar.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//
//  Created by Nathan Tannar on 8/25/17.
//

import UIKit

internal extension NSNotification {
    
    var event: KeyboardEvent {
        switch self.name {
        case UIResponder.keyboardWillShowNotification:
            return .willShow
        case UIResponder.keyboardDidShowNotification:
            return .didShow
        case UIResponder.keyboardWillHideNotification:
            return .willHide
        case UIResponder.keyboardDidHideNotification:
            return .didHide
        case UIResponder.keyboardWillChangeFrameNotification:
            return .willChangeFrame
        case UIResponder.keyboardDidChangeFrameNotification:
            return .didChangeFrame
        default:
            return .unknown
        }
    }
    
    var timeInterval: TimeInterval? {
        guard let value = userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber else { return nil }
        return TimeInterval(truncating: value)
    }
    
    var animationCurve: UIView.AnimationCurve? {
        guard let index = (userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.intValue else { return nil }
        guard index >= 0 && index <= 3 else { return .linear }
        return UIView.AnimationCurve.init(rawValue: index) ?? .linear
    }
    
    var animationOptions: UIView.AnimationOptions {
        guard let curve = animationCurve else { return [] }
        switch curve {
        case .easeIn:
            return .curveEaseIn
        case .easeOut:
            return .curveEaseOut
        case .easeInOut:
            return .curveEaseInOut
        case .linear:
            return .curveLinear
        @unknown default:
            return []
        }
    }
    
    var startFrame: CGRect? {
        return (userInfo?[UIResponder.keyboardFrameBeginUserInfoKey] as? NSValue)?.cgRectValue
    }
    
    var endFrame: CGRect? {
        return (userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
    }
    
    var isForCurrentApp: Bool? {
        return (userInfo?[UIResponder.keyboardIsLocalUserInfoKey] as? NSNumber)?.boolValue
    }
    
}
