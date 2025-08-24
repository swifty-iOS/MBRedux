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

// MARK: -

/// Protocol that represents the state in the Redux flow.
/// The state must conform to `Hashable` to enable comparisons based on hash values.
public protocol StateType: Equatable, Sendable {
    /** Must be adopted by state */
}

/// Allow optional state type
extension Optional: StateType where Wrapped: StateType {
    /** use optional state now if required */
}

/// Extend the `StateType` protocol to provide a custom equality operator (`==`).
/// This compares two `StateType` instances by their `hashValue`.
public extension StateType where Self: Hashable {
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

// MARK: -

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

// MARK: - ReduxReducer

// Typealias that defines the `Reducer` type.
// A `Reducer` takes a `ReduxAction` and a current state (`StateType`) and returns an updated state (`StateType`).
public typealias ReduxReducer<StateType> = @Sendable (ReduxAction, StateType) -> StateType

// MARK: - ReduxStatePublisherType

/// A protocol that defines methods for publishing state updates in a Redux-style architecture.
protocol ReduxStatePublisherType<State>: Publisher where Failure == Never, Output == State {
    /// The associated type that conforms to the `StateType` protocol,
    /// representing the application's state.
    associatedtype State: StateType

    // MARK: Methods

    func getState() -> State
    func setState(_ state: State)
}

// MARK: -

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

    /// Subscribe the state
    func subscribe() -> AnyPublisher<State, Never>
}

// MARK: - Implemenation

// --------------------------
// **  Implemenation **
// --------------------------

/// A concrete implementation of `ReduxMiddlewareStore`.
/// Holds closures for retrieving the current state and dispatching actions.
private struct ReduxMiddlewareStoreContext<State: StateType>: ReduxMiddlewareStore {
    let getState: GetReduxState<State>
    let dispatchAsync: ReduxActionDispatch
}

// MARK: -

/// A private class that conforms to the `ReduxStatePublisherType` protocol.
/// This class handles the subscription to state updates and allows for reacting to changes in the state.
private struct ReduxStatePublisher<State: StateType>: ReduxStatePublisherType {
    private let currentState: CurrentValueSubject<State, Never>

    init(state: State) {
        currentState = .init(state)
    }

    func receive<S>(subscriber: S) where S: Subscriber, Never == S.Failure, State == S.Input {
        currentState.subscribe(subscriber)
    }

    func getState() -> State {
        currentState.value
    }

    func setState(_ state: State) {
        currentState.send(state)
    }
}

// MARK: -

/// A private class that conforms to the `ReduxStoreType` protocol.
/// This class is responsible for managing the application's state and dispatching actions
/// to update the state using a reducer.
private final class ReduxStore<State: StateType>: ReduxStoreType, @unchecked Sendable {
    // A dedicated queue to synchronize state changes and actions.
    private let reduxQueue = DispatchQueue(label: "com.reduxStore.queue")

    // Subscription manager to handle state change notifications.
    private let publisher: any ReduxStatePublisherType<State>
    // get current state
    lazy var getState: GetReduxState<State> = { [unowned self] in
        reduxQueue.sync {
            publisher.getState()
        }
    }

    init(publisher: any ReduxStatePublisherType<State>) {
        self.publisher = publisher
    }

    /// Dispatches an action to update the state.
    /// The state is updated inside a sync block to ensure thread safety.
    func dispatch(action: ReduxAction, reducer: @escaping ReduxReducer<State>) {
        let newState = reducer(action, publisher.getState())
        // Notify subscribers that the state will be updated.
        publisher.setState(newState)
    }

    func subscribe() -> AnyPublisher<State, Never> {
        publisher.eraseToAnyPublisher()
    }
}

// MARK: - Redux

/// Redux class encapsulates the entire Redux flow.
/// This class includes functionality to dispatch actions, and state subscription.
@available(macOS 13.0.0, *)
public final class Redux<State: StateType>: Sendable {
    // The current state of the store, which can be nil initially.
    fileprivate let store: any ReduxStoreType<State>
    // The reducer to manage state changes, initialized when registered.
    private let reducer: ReduxReducer<State>
    // The middleware for side-effects
    private let middlewares: [ReduxMiddleware<State>]
    private let dispatchQueue = DispatchQueue(label: "com.redux.reducer.dispatchQueue")

    public init(
        state: State,
        middlewares: [ReduxMiddleware<State>] = [],
        reducer: @escaping ReduxReducer<State>
    ) {
        self.reducer = reducer
        store = ReduxStore<State>(publisher: ReduxStatePublisher<State>(state: state))
        self.middlewares = middlewares.reversed()
    }

    /// Dispatches an action to update the state.
    /// The state is updated inside a sync block to ensure thread safety.
    public func dispatch(_ action: ReduxAction) {
        let dispatcher = applyMiddlewares(
            context: ReduxMiddlewareStoreContext(
                getState: getState,
                dispatchAsync: { [weak self] action in
                    self?.middlewareDispatch(action: action)
                }
            ),
            baseDispatch: { [weak self] action in guard let self else { return }
                store.dispatch(action: action, reducer: reducer)
            }
        )

        dispatchQueue.async {
            dispatcher(action)
        }
    }

    // create middlewaer chain before dispacting action
    private func applyMiddlewares(
        context: any ReduxMiddlewareStore<State>,
        baseDispatch: @escaping ReduxActionDispatch
    ) -> ReduxActionDispatch {
        middlewares.reduce(baseDispatch) { next, middleware in
            middleware(context, next)
        }
    }

    private func middlewareDispatch(action: ReduxAction) {
        dispatchQueue.async { [weak self] in
            self?.dispatch(action)
        }
    }
}

// MARK: - Helper method

@available(macOS 13.0.0, *)
public extension Redux {
    /// Return value of State
    var getState: @Sendable () -> State {
        store.getState
    }

    /// Return value at specifed path from state
    func getState<P>(_ childState: KeyPath<State, P>) -> P where P: StateType {
        getState()[keyPath: childState]
    }

    /// Returns a publisher that emits the entire state when it changes.
    func subscribe() -> AnyPublisher<State, Never> {
        store.subscribe()
            .dropFirst()
            .eraseToAnyPublisher()
    }

    /// Returns a publisher that emits a specific part of the state (based on the path) when it changes.
    func subscribe<P>(_ childState: KeyPath<State, P>) -> AnyPublisher<P, Never> where P: StateType {
        subscribe()
            .map { $0[keyPath: childState] }
            .eraseToAnyPublisher()
    }

    /// Returns a publisher that emits a specific part of the state (based on the path) when it changes.
    func subscribe<P>(path: KeyPath<State, P>) -> AnyPublisher<P, Never> where P: Hashable {
        subscribe()
            .map { $0[keyPath: path] }
            .eraseToAnyPublisher()
    }

    /// Returns a publisher that emits the entire state when it changes.
    func subscribe(subscription: @escaping (State) -> Void) -> AnyCancellable {
        subscribe().sink(receiveValue: subscription)
    }

    /// Returns a publisher that emits a specific part of the state (based on the path) when it changes.
    func subscribe<P>(_ childState: KeyPath<State, P>,
                      subscription: @escaping (P) -> Void) -> AnyCancellable where P: StateType {
        subscribe(childState).sink(receiveValue: subscription)
    }

    /// Returns a publisher that emits a specific part of the state (based on the path) when it changes.
    func subscribe<P>(path: KeyPath<State, P>,
                      subscription: @escaping (P) -> Void) -> AnyCancellable where P: Hashable {
        subscribe(path: path).sink(receiveValue: subscription)
    }
}
