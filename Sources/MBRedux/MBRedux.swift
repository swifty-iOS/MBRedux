// The Swift Programming Language
// https://docs.swift.org/swift-book
//
// Created by Manish on 03/04/25.
//

import Combine
import Foundation

/// Protocol representing an action in the Redux flow.
/// Any action that is dispatched must conform to this protocol.
public protocol ReduxAction: Sendable {
    /** Use to all action */
}

// MARK: - StateType

/// Protocol that represents the state in the Redux flow.
/// The state must conform to `Hashable` to enable comparisons based on hash values.
public protocol StateType: Hashable, Sendable {
    /** Must be adopted by state */
}

/// Allow optional state type
extension Optional: StateType where Wrapped: StateType {
    /** use optional state now if required */
}

/// Extend the `StateType` protocol to provide a custom equality operator (`==`).
/// This compares two `StateType` instances by their `hashValue`.
public extension StateType {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.hashValue == rhs.hashValue
    }
}

// MARK: -

/// A typealias for a function that can dispatch a Redux action asynchronously.
/// The function is marked as `@Sendable` to support concurrency-safe usage.
public typealias ReduxActionDispatch = @Sendable (ReduxAction) -> Void

/// A typealias for a closure that returns the current Redux state.
/// This closure is marked `@Sendable` so it can safely be used in concurrent contexts.
///
/// - Returns: The current state of type `State`.
public typealias GetReduxState<State> = @Sendable () -> State

/// A protocol representing the middleware store context used by Redux middleware.
/// Provides access to the current state and an async dispatch function.
/// The protocol is constrained to `Sendable` for use in concurrent environments.
public protocol ReduxMiddlewareStore<State>: Sendable {
    associatedtype State: StateType

    /// A closure that returns the current state of the store.
    var getState: GetReduxState<State> { get }

    /// A closure that allows dispatching actions asynchronously.
    var dispatchAsync: ReduxActionDispatch { get }
}

// MARK: -

/// A typealias defining the structure of a Redux middleware.
/// It takes a middleware store and a reference to the next dispatch function,
/// and returns a new dispatch function that can intercept or modify actions.
///
/// - Parameters:
///   - store: The middleware store providing access to state and dispatch.
///   - next: The next dispatch function in the chain.
/// - Returns: A new dispatch function that wraps/intercepts the original one.
public typealias ReduxMiddleware<StateType> = @Sendable (
    any ReduxMiddlewareStore<StateType>,
    @escaping ReduxActionDispatch
) -> ReduxActionDispatch

// MARK: -

/// A concrete implementation of `ReduxMiddlewareStore`.
/// Holds closures for retrieving the current state and dispatching actions.
private struct ReduxMiddlewareStoreContext<State: StateType>: ReduxMiddlewareStore {
    let getState: GetReduxState<State>
    let dispatchAsync: ReduxActionDispatch
}

// MARK: - ReduxMiddlewareImplentation

/// A helper class responsible for applying a series of middleware functions
/// to dispatched actions in a state container (e.g., a Redux store).
///
/// - Note: This implementation uses a static `state` and `action` at the time of middleware composition.
///         If your middleware needs access to dynamic state or multiple actions, consider passing `getState` instead.
@available(macOS 13.0.0, *)
private struct ReduxMiddlewareMapper<State: StateType>: Sendable {
    /// An array of middleware functions that operate on a specific state type and `ReduxAction`.
    /// Each middleware can intercept, modify, or respond to dispatched actions.
    let middlewares: [ReduxMiddleware<State>]

    /// Initializes the middleware manager with a list of middleware functions.
    ///
    /// - Parameter middlewares: An array of middleware functions to be applied.
    init(middlewares: [ReduxMiddleware<State>]) {
        self.middlewares = middlewares.reversed()
    }

    /// Applies all middleware to a given dispatch chain.
    ///
    /// This function composes the middleware pipeline by wrapping the `baseDispatch`
    /// function with each middleware, starting from the last and working backward.
    ///
    /// - Parameters:
    ///   - state: The current state at the time of dispatch.
    ///   - action: The action being dispatched.
    ///   - baseDispatch: The base dispatch function, typically responsible for invoking the reducer.
    ///
    /// - Returns: A new `ReduxActionDispatch` function that has all middleware applied.
    func applyMiddlewares(
        context: any ReduxMiddlewareStore<State>,
        baseDispatch: @escaping ReduxActionDispatch
    ) -> ReduxActionDispatch {
        middlewares.reduce(baseDispatch) { next, middleware in
            middleware(context, next)
        }
    }
}

// MARK: - ReduxReducer

// Typealias that defines the `Reducer` type.
// A `Reducer` takes a `ReduxAction` and a current state (`StateType`) and returns an updated state (`StateType`).
public typealias ReduxReducer<StateType> = @Sendable (ReduxAction, StateType) -> StateType

// MARK: - ReduxStatePublisherType

/// A protocol that defines methods for publishing state updates in a Redux-style architecture.
protocol ReduxStatePublisherType<State>: Sendable {
    /// The associated type that conforms to the `StateType` protocol,
    /// representing the application's state.
    associatedtype State: StateType

    // MARK: Methods

    /// Called before the state is updated. This can be used for any preparations or actions before the update occurs.
    /// - Parameter state: The current state that is about to be updated, or `nil` if no previous state exists.
    func willUpdateState(_ state: State)

    /// Called after the state has been updated. This can be used to trigger actions or updates in response to the new state.
    /// - Parameter state: The updated state, or `nil` if the state was reset.
    func didUpdateState(_ state: State)
}

// MARK: - ReduxSubscription

/// A private class that conforms to the `ReduxStatePublisherType` protocol.
/// This class handles the subscription to state updates and allows for reacting to changes in the state.
private struct ReduxSubscription<State: StateType>: ReduxStatePublisherType, @unchecked Sendable {
    // Publishers to track the state before and after an update
    private let beforeSateUpdate = PassthroughSubject<State, Never>()
    private let afterStateUpdate = PassthroughSubject<State, Never>()

    /// Sends the state before it is updated
    func willUpdateState(_ state: State) {
        beforeSateUpdate.send(state)
    }

    /// Sends the state after it is updated
    func didUpdateState(_ state: State) {
        afterStateUpdate.send(state)
    }

    /// Combines `beforeStateUpdate` and `afterStateUpdate` to emit the new state only when it changes.
    /// This is useful for notifying subscribers only when the state actually changes.
    func subscribe() -> AnyPublisher<State, Never> {
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
    func subscribe<P: Hashable>(path: KeyPath<State, P>) -> AnyPublisher<P, Never> {
        beforeSateUpdate.map {
            // Access the state at the specific path before the update
            $0[keyPath: path]
        }.combineLatest(
            afterStateUpdate.map {
                // Access the state at the specific path after the update
                $0[keyPath: path]
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
public protocol ReduxStoreType<State>: Sendable {
    /// The associated type that conforms to the `StateType` protocol, representing the store's state.
    associatedtype State: StateType

    /// Returns the current state of the store.
    /// - Returns: The current state of type `S`, or `nil` if the state is not available.
    var getState: GetReduxState<State> { get }

    /// Dispatches an action to the store, triggering a state update via the provided reducer.
    /// - Parameters:
    ///   - action: The action that represents a change or event in the application.
    ///   - reducer: The reducer that will handle the action and update the state accordingly.
    func dispatch(action: ReduxAction, reducer: @escaping ReduxReducer<State>)
}

// MARK: - ReduxStore

/// A private class that conforms to the `ReduxStoreType` protocol.
/// This class is responsible for managing the application's state and dispatching actions
/// to update the state using a reducer.
private final class ReduxStore<State: StateType>: ReduxStoreType, @unchecked Sendable {
    // A dedicated queue to synchronize state changes and actions.
    private let reduxQueue = DispatchQueue(label: "com.reduxStore.queue")
    // The current state of the store, which can be nil initially.
    var state: State
    // Subscription manager to handle state change notifications.
    let publisher: any ReduxStatePublisherType<State>
    // get current state
    lazy var getState: GetReduxState<State> = { [unowned self] in
        reduxQueue.sync {
            self.state
        }
    }

    init(publisher: any ReduxStatePublisherType<State>, state: State) {
        self.publisher = publisher
        self.state = state
    }

    /// Dispatches an action to update the state.
    /// The state is updated inside a sync block to ensure thread safety.
    func dispatch(action: ReduxAction, reducer: @escaping ReduxReducer<State>) {
        reduxQueue.async { [weak self] in
            guard let self else { return }
            // Notify subscribers that the state will be updated.
            publisher.willUpdateState(state)
            // Apply the reducer to the current state and the action.
            state = reducer(action, state)
            // Notify subscribers that the state has been updated.
            publisher.didUpdateState(state)
        }
    }
}

// MARK: - Redux

/// Redux class encapsulates the entire Redux flow.
/// This class includes functionality to dispatch actions, and state subscription.
@available(macOS 13.0.0, *)
public final class Redux<State: StateType>: Sendable {
    // The current state of the store, which can be nil initially.
    private let store: any ReduxStoreType<State>
    // Manage all subscriptions
    private let subscription: ReduxSubscription<State> = .init()
    // The reducer to manage state changes, initialized when registered.
    private let reducer: ReduxReducer<State>
    // The middleware for side-effects
    private let middleware: ReduxMiddlewareMapper<State>
    public init(
        state: State,
        middlewares: [ReduxMiddleware<State>] = [],
        reducer: @escaping ReduxReducer<State>
    ) {
        self.reducer = reducer
        store = ReduxStore<State>(publisher: subscription, state: state)
        middleware = .init(middlewares: middlewares)
    }

    /// Dispatches an action to update the state.
    /// The state is updated inside a sync block to ensure thread safety.
    public func dispatch(_ action: ReduxAction) {
        let dispatcher = middleware.applyMiddlewares(
            context: ReduxMiddlewareStoreContext(
                getState: getState,
                dispatchAsync: middlewareAsyncDispatch
            ),
            baseDispatch: { [weak self] action in guard let self else { return }
                store.dispatch(action: action, reducer: reducer)
            }
        )
        dispatcher(action)
    }

    private func middlewareAsyncDispatch(action: ReduxAction) {
        DispatchQueue.global(qos: .userInitiated)
            .async { [weak self] in
                self?.dispatch(action)
            }
    }
}

// MARK: - Helper method

@available(macOS 13.0.0, *)
public extension Redux {
    /// Return value of State
    func getState() -> State {
        store.getState()
    }

    /// Return value at specifed path from state
    func getState<P>(path: KeyPath<State, P>) -> P {
        getState()[keyPath: path]
    }

    /// Returns a publisher that emits the entire state when it changes.
    func subscribe() -> AnyPublisher<State, Never> {
        subscription.subscribe()
            .flatMap { state in
                Future { promise in
                    DispatchQueue.global(qos: .userInitiated).async {
                        promise(.success(state))
                    }
                }
            }
            .eraseToAnyPublisher()
    }

    /// Returns a publisher that emits a specific part of the state (based on the path) when it changes.
    func subscribe<P: Hashable>(path: KeyPath<State, P>) -> AnyPublisher<P, Never> {
        subscription.subscribe(path: path)
            .receive(on: DispatchQueue.global())
            .eraseToAnyPublisher()
    }

    /// Returns a publisher that emits the entire state when it changes.
    func subscribe(subscription: @escaping (State) -> Void) -> AnyCancellable {
        subscribe().sink(receiveValue: subscription)
    }

    /// Returns a publisher that emits a specific part of the state (based on the path) when it changes.
    func subscribe<P: Hashable>(path: KeyPath<State, P>, subscription: @escaping (P) -> Void) -> AnyCancellable {
        subscribe(path: path).sink(receiveValue: subscription)
    }
}
