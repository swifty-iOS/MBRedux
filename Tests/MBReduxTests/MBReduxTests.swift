// The Swift Programming Language
// https://docs.swift.org/swift-book
//
// Created by Manish on 03/04/25.
//

import Combine
@testable import MBRedux
import XCTest

// Define a simple test state and action
private class TestState: StateType, Hashable {
    let value: Int
    var user: MockSateUser?

    init(value: Int, user: MockSateUser? = nil) {
        self.value = value
        self.user = user
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }
}

private class MockSateUser: StateType, Equatable {
    let username: String

    init(username: String) {
        self.username = username
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(username)
    }
}

private enum TestAction: ReduxAction, Equatable {
    case increment
    case decrement
    case noChange
    case user(String)
}

private func mockReducer(action: ReduxAction, state: TestState) -> TestState {
    switch action {
    case TestAction.increment:
        return TestState(value: (state.value) + 1, user: state.user)
    case TestAction.decrement:
        return TestState(value: (state.value) - 1, user: state.user)
    case let TestAction.user(username):
        let newState = state
        newState.user = .init(username: username)
        return newState
    default:
        return state
    }
}

final class ReduxStoreTests: XCTestCase {
    // The Redux store instance to test
    private var store: Redux<TestState>!
    let testUserName = "testuser"
    // The cancellables to hold subscriptions
    var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        // Initialize the store with an initial state
        store = Redux<TestState>(state: TestState(value: 0), reducer: mockReducer)
    }

    override func tearDown() {
        // Reset the store and cancellables after each test
        cancellables.removeAll()
        store = nil
        super.tearDown()
    }

    func testDispatchAction() {
        // Dispatch actions
        store.dispatch(TestAction.increment)
        store.dispatch(TestAction.increment)
        // Check the state after dispatching
        XCTAssertEqual(store.getState().value, 2)
        XCTAssertEqual(store.getState(path: \.value), 2)
    }

    func testStateSubscription() {
        // Expectation for state change subscription
        let expectation = expectation(description: "State should be updated")
        store.subscribe()
            .sink { newState in
                if newState.value == 1 {
                    expectation.fulfill() // Fulfill when state is updated to value 1
                }
            }
            .store(in: &cancellables)

        // Dispatch increment action
        store.dispatch(TestAction.increment)

        // Wait for the state change to be triggered
        wait(for: [expectation], timeout: 0.5)
    }

    func testStatePathSubscription() {
        // Expectation for state path change subscription
        let expectation = self.expectation(description: "State path value should be updated")
        store.subscribe(path: \.value)
            .sink { newValue in
                if newValue == 1 {
                    expectation.fulfill() // Fulfill when value is updated to 1
                }
            }
            .store(in: &cancellables)
        // Dispatch increment action
        store.dispatch(TestAction.increment)
        // Wait for the state path change to be triggered
        wait(for: [expectation], timeout: 0.5)
    }

    func testStateTypeSubscription() {
        // Expectation for state path change subscription
        let expectation = self.expectation(description: "State type should be updated")
        store.subscribe(path: \.user)
            .sink { [testUserName] newValue in
                if newValue?.username == testUserName {
                    expectation.fulfill() // Fulfill when value is updated to 1
                }
            }
            .store(in: &cancellables)
        // Dispatch increment action
        store.dispatch(TestAction.user(testUserName))
        // Wait for the state path change to be triggered
        wait(for: [expectation], timeout: 0.5)
    }

    @MainActor
    // If this fails adjust timout
    func testNoStateChange() {
        let testUserName = "testuser"
        // Expectation for state path change subscription
        let expectation = self.expectation(description: "State change should not be call")
        store.dispatch(TestAction.user(testUserName))
        XCTAssertEqual(store.getState(path: \.user?.username), testUserName)
        // Check for flag if subscriber calls
        var isUpdateCalled = false
        store.subscribe(path: \.user)
            .sink { _ in
                isUpdateCalled = true
            }
            .store(in: &cancellables)
        // dispach no action
        store.dispatch(TestAction.user(testUserName))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertFalse(isUpdateCalled)
            expectation.fulfill()
        }
        // Wait for both before and after state update expectations
        wait(for: [expectation], timeout: 1)
    }
}

// MARK: -

final class ReduxStoreOptinalTests: XCTestCase {
    struct SomeAction: ReduxAction {
        let name: String?
    }

    static func mockOptionalReducer(_ action: ReduxAction?, _ state: TestState?) -> TestState? {
        if let action = action as? SomeAction {
            return TestState(name: action.name)
        }
        return state
    }

    struct TestState: StateType {
        var name: String?
    }

    private var store: Redux<TestState?>!
    let testUserName = "testuser"
    // The cancellables to hold subscriptions
    var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        // Initialize the store with an initial state
        store = Redux<TestState?>(state: nil, reducer: Self.mockOptionalReducer)
    }

    override func tearDown() {
        // Reset the store and cancellables after each test
        cancellables.removeAll()
        store = nil
        super.tearDown()
    }

    func testOptionalRedux() {
        XCTAssertNil(store.getState())
        store.dispatch(SomeAction(name: nil))
        XCTAssertNotNil(store.getState())
        XCTAssertNil(store.getState()?.name)

        let expectation = self.expectation(description: "State type should be updated")
        store.subscribe(path: \.self?.name)
            .sink { name in
                if name == "test" {
                    expectation.fulfill() // Fulfill when value is updated to 1
                }
            }
            .store(in: &cancellables)
        // Dispatch increment action
        store.dispatch(SomeAction(name: "test"))
        // Wait for the state path change to be triggered
        wait(for: [expectation], timeout: 0.5)
    }
}

// MARK: -

final class ReduxStoreMiddleTests: XCTestCase {
    // The Redux store instance to test
    private var store: Redux<TestState>!
    let testUserName = "testuser"
    // The cancellables to hold subscriptions
    var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        // Initialize the store with an initial state
        store = Redux<TestState>(
            state: TestState(value: 0),
            middlewares: [Self.incrementMiddleware, Self.decrementMiddleware],
            reducer: mockReducer
        )
    }

    override func tearDown() {
        // Reset the store and cancellables after each test
        cancellables.removeAll()
        store = nil
        super.tearDown()
    }

    @MainActor
    func testMiddlewareIncrement() {
        let expectation = expectation(description: "State should not be updated")
        var isUpdateCalled = false
        store.subscribe()
            .sink { _ in
                isUpdateCalled = true
            }
            .store(in: &cancellables)

        // Dispatch increment action
        store.dispatch(TestAction.increment)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertFalse(isUpdateCalled)
            expectation.fulfill()
        }
        // Wait for the state change to be triggered
        wait(for: [expectation], timeout: 0.5)
    }

    @MainActor
    func testMiddlewareDecrement() {
        let expectation = expectation(description: "State should not be updated")
        store.subscribe()
            .sink { newState in
                XCTAssertEqual(newState.value, 1)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Dispatch increment action
        store.dispatch(TestAction.decrement)
        // Wait for the state change to be triggered
        wait(for: [expectation], timeout: 0.5)
    }

    // MARK: - Mock middleware

    fileprivate static func incrementMiddleware(state _: TestState, action: ReduxAction) -> (@escaping ReduxActionDispatch) -> ReduxActionDispatch {
        return { next in
            { action in
                if (action as? TestAction) == .increment {
                    next(TestAction.noChange)
                } else {
                    next(action)
                }
            }
        }
    }

    // MARK: - Mock middleware

    fileprivate static func decrementMiddleware(state _: TestState, action: ReduxAction) -> (@escaping ReduxActionDispatch) -> ReduxActionDispatch {
        return { next in
            { action in
                if (action as? TestAction) == .decrement {
                    next(TestAction.increment)
                } else {
                    next(action)
                }
            }
        }
    }
}
