// The Swift Programming Language
// https://docs.swift.org/swift-book
//
// Created by Manish on 03/04/25.
//

import Combine
import Foundation

/// Protocol representing an action in the Redux flow.
/// Any action that is dispatched must conform to this protocol.
public protocol ReduxAction {
    /** Use to all action */
}

// MARK: - StateType

/// Protocol that represents the state in the Redux flow.
/// The state must conform to `Hashable` to enable comparisons based on hash values.
public protocol StateType: Hashable {
    /** Must be adopted by state */
}

/// Extend the `StateType` protocol to provide a custom equality operator (`==`).
/// This compares two `StateType` instances by their `hashValue`.
public extension StateType {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.hashValue == rhs.hashValue
    }
}

// MARK: -

// Typealias that defines the `Reducer` type.
// A `Reducer` takes a `ReduxAction` and a current state (`S?`) and returns an updated state (`S?`).
public typealias Reducer<StateType> = (ReduxAction, StateType?) -> StateType?

// MARK: - ReduxStatePublisherType

/// A protocol that defines methods for publishing state updates in a Redux-style architecture.
protocol ReduxStatePublisherType<State> {
    /// The associated type that conforms to the `StateType` protocol,
    /// representing the application's state.
    associatedtype State: StateType

    // MARK: Methods

    /// Called before the state is updated. This can be used for any preparations or actions before the update occurs.
    /// - Parameter state: The current state that is about to be updated, or `nil` if no previous state exists.
    func willUpdateState(_ state: State?)

    /// Called after the state has been updated. This can be used to trigger actions or updates in response to the new state.
    /// - Parameter state: The updated state, or `nil` if the state was reset.
    func didUpdateState(_ state: State?)
}

// MARK: - ReduxSubscription

/// A private class that conforms to the `ReduxStatePublisherType` protocol.
/// This class handles the subscription to state updates and allows for reacting to changes in the state.
private class ReduxSubscription<S: StateType>: ReduxStatePublisherType {
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

// MARK: - ReduxStoreType

/// A protocol that defines the required methods for a Redux store.
/// This protocol is responsible for providing access to the application's state
/// and dispatching actions to update the state.
protocol ReduxStoreType<State> {
    /// The associated type that conforms to the `StateType` protocol, representing the store's state.
    associatedtype State: StateType

    /// Returns the current state of the store.
    /// - Returns: The current state of type `S`, or `nil` if the state is not available.
    func getState() -> State?

    /// Dispatches an action to the store, triggering a state update via the provided reducer.
    /// - Parameters:
    ///   - action: The action that represents a change or event in the application.
    ///   - reducer: The reducer that will handle the action and update the state accordingly.
    func dispatch(action: ReduxAction, reducer: Reducer<State>)
}

// MARK: - ReduxStore

/// A private class that conforms to the `ReduxStoreType` protocol.
/// This class is responsible for managing the application's state and dispatching actions
/// to update the state using a reducer.
private class ReduxStore<S: StateType>: ReduxStoreType {
    // A dedicated queue to synchronize state changes and actions.
    private let reduxQueue = DispatchQueue(label: "com.reduxStore.queue")
    // The current state of the store, which can be nil initially.
    var state: S?
    // Subscription manager to handle state change notifications.
    let publisher: any ReduxStatePublisherType<S>

    init(publisher: any ReduxStatePublisherType<S>) {
        self.publisher = publisher
        state = nil
    }

    /// Dispatches an action to update the state.
    /// The state is updated inside a sync block to ensure thread safety.
    func dispatch(action: ReduxAction, reducer: Reducer<S>) {
        reduxQueue.sync { [weak self] in
            guard let self else {
                return
            }
            // Notify subscribers that the state will be updated.
            publisher.willUpdateState(state)
            // Apply the reducer to the current state and the action.
            state = reducer(action, state)
            // Notify subscribers that the state has been updated.
            publisher.didUpdateState(state)
        }
    }

    /// Get current state
    func getState() -> S? {
        state
    }
}

/// Redux class encapsulates the entire Redux flow.
/// This class includes functionality to dispatch actions, and state subscription.
public class Redux<S: StateType> {
    // The current state of the store, which can be nil initially.
    private let store: any ReduxStoreType<S>
    // Manage all subscriptions
    private let subscription: ReduxSubscription<S> = .init()
    // The reducer to manage state changes, initialized when registered.
    private let reducer: Reducer<S>

    public init(reducer: @escaping Reducer<S>) {
        self.reducer = reducer
        store = ReduxStore<S>(publisher: subscription)
    }

    /// Dispatches an action to update the state.
    /// The state is updated inside a sync block to ensure thread safety.
    public func dispatch(_ action: ReduxAction) {
        store.dispatch(action: action, reducer: reducer)
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
        store.getState()
    }

    /// Return value at specifed path from state
    public func getState<P>(path: KeyPath<S, P>) -> P? {
        getState()?[keyPath: path]
    }
}
