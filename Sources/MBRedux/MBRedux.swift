// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import Combine

/// Protocol representing an action in the Redux flow.
/// Any action that is dispatched must conform to this protocol.
public protocol ReduxAction {
    /** Use to all action*/
}

/// Protocol that represents the state in the Redux flow.
/// The state must conform to `Hashable` to enable comparisons based on hash values.
public protocol StateType: Hashable {
    /** Must be adopted by state*/
}

/// Extend the `StateType` protocol to provide a custom equality operator (`==`).
/// This compares two `StateType` instances by their `hashValue`.
public extension StateType {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.hashValue == rhs.hashValue
    }
}

// Typealias that defines the `Reducer` type.
// A `Reducer` takes a `ReduxAction` and a current state (`S?`) and returns an updated state (`S?`).
public typealias Reducer<S: StateType> = (ReduxAction, S?) -> S?

// Private struct to encapsulate the reducer logic.
// This struct holds the reducer function and provides an `apply` method to apply actions to the state.
private struct ReduxReducer<S: StateType> {
    // The reducer function
    private let reducer: Reducer<S>
    
    // Initializer to set the reducer function
    init(reducer: @escaping Reducer<S>) {
        self.reducer = reducer
    }
    
    // Applies the given action to the current state, returning the updated state
    func apply(action: ReduxAction, toState state: S?) -> S? {
        return reducer(action, state)
    }
}

/// Private struct to manage state updates and subscriptions.
/// This struct allows subscribers to listen for changes in state before and after the update.
private struct ReduxSubscription<S: StateType> {
    
    // Publishers to track the state before and after an update
    private let beforeSateUpdate = PassthroughSubject<S?, Never>()
    private let afterStateUpdate = PassthroughSubject<S?, Never>()
    
    /// Sends the state before it is updated
    func willUpdateState(_ state: S?) {
        beforeSateUpdate.send(state)
    }
    
    /// Sends the state after it is updated
    func didUpdateState(_ state: S?) {
        afterStateUpdate.send(state)
    }
    
    /// Combines `beforeStateUpdate` and `afterStateUpdate` to emit the new state only when it changes.
    /// This is useful for notifying subscribers only when the state actually changes.
    func subscribe() -> AnyPublisher<S?, Never> {
        beforeSateUpdate
            .combineLatest(afterStateUpdate)
            .filter {
                // Only emit when the state has changed (checked by hashValue)
                $0.hashValue != $1.hashValue
            }.map { _, newState in
                newState
            }.eraseToAnyPublisher() // Returns a publisher
    }
    
    /// Subscribe to a specific path within the state (using KeyPath) and emit only the changed part of the state.
    func subscribe<P: Hashable>(path: KeyPath<S, P>) -> AnyPublisher<P, Never> {
        beforeSateUpdate.map {
            // Access the state at the specific path before the update
            $0?[keyPath: path]
        }.combineLatest(
            afterStateUpdate.map {
                // Access the state at the specific path after the update
                $0?[keyPath: path]
            }
        ).filter {
            // Only emit when the value at the specific path has changed
            $0.hashValue != $1.hashValue
        }
        .compactMap { _, newValue in
            newValue // Return the updated value
        }.eraseToAnyPublisher() // Return a publisher for the specific value
    }
}

/// ReduxStore class encapsulates the entire Redux flow for managing the state.
/// This class includes functionality to register reducers, dispatch actions, and manage state updates.
public class ReduxStore<S: StateType> {
    
    // The current state of the store, which can be nil initially.
    private var state: S?
    
    // The reducer to manage state changes, initialized when registered.
    private var reducer: ReduxReducer<S>?
    
    // Subscription manager to handle state change notifications.
    private let subscription: ReduxSubscription<S> = .init()
    
    // A dedicated queue to synchronize state changes and actions.
    private let reduxQueue = DispatchQueue(label: "com.reduxStore.queue")
    
    /// Initializes an empty store with no state.
    public init() {
        self.state = nil
    }
    
    /// Registers a reducer function, but ensures that it can only be registered once.
    /// Throws an error if a reducer is already registered.
    public func register(reducer: @escaping Reducer<S>) throws {
        guard self.reducer == nil else {
            // Throw error if a reducer is already registered.
            throw NSError(domain: "ReduxError.reducerAlreadyRegistered", code: -1)
        }
        // Initialize the ReduxReducer with the provided reducer function.
        self.reducer = ReduxReducer(reducer: reducer)
    }
    
    /// Dispatches an action to update the state.
    /// The state is updated inside a sync block to ensure thread safety.
    public func dispatch(_ action: ReduxAction) {
        reduxQueue.sync { [weak self] in
            guard let self else {
                return
            }
            // Notify subscribers that the state will be updated.
            subscription.willUpdateState(state)
            // Apply the reducer to the current state and the action.
            state = reducer?.apply(action: action, toState: state)
            // Notify subscribers that the state has been updated.
            subscription.didUpdateState(state)
        }
    }
    
    /// Returns a publisher that emits the entire state when it changes.
    public func subscribe() -> AnyPublisher<S?, Never> {
        subscription.subscribe()
    }
    
    /// Returns a publisher that emits a specific part of the state (based on the path) when it changes.
    public func subscribe<P: Hashable>(path: KeyPath<S, P>) -> AnyPublisher<P, Never> {
        subscription.subscribe(path: path)
    }
    
    /// Return value of State
    public func getState() -> S? {
        state
    }
    
    /// Return value at specifed path from state
    public func getState<P>(path: KeyPath<S, P>) -> P? {
        getState()?[keyPath: path]
    }
}
