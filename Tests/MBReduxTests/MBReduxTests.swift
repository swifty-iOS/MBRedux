// The Swift Programming Language
// https://docs.swift.org/swift-book
//
// Created by Manish on 03/04/25.
//

import Combine
@testable import MBRedux
import XCTest

// Define a simple test state and action
private final class TestState: StateType, Hashable, @unchecked Sendable {
    let value: Int
    var user: MockSateUser?

    init(value: Int, user: MockSateUser? = nil) {
        self.value = value
        self.user = user
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(value)
        hasher.combine(user?.hashValue)
    }
}

private final class MockSateUser: StateType, Hashable, @unchecked Sendable {
    var username: String

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
    case username(String)
    case update(Int)
}

private func mockReducer(action: ReduxAction, state: TestState) -> TestState {
    guard let action = action as? TestAction else {
        return state
    }
    switch action {
    case TestAction.increment:
        return TestState(value: (state.value) + 1, user: state.user)

    case TestAction.decrement:
        return TestState(value: (state.value) - 1, user: state.user)

    case let TestAction.user(username):
        state.user = .init(username: username)
        return state

    case let TestAction.username(username):
        state.user?.username = username
        return state

    case let .update(value):
        return TestState(value: value, user: state.user)

    case .noChange:
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [store] in
            XCTAssertEqual(store?.getState().value, 2)
        }
    }

    func testStateSubscription() {
        // Expectation for state change subscription
        let expectation = expectation(description: "State should be updated")
        store.subscribe()
            .sink { newState in
                XCTAssertEqual(newState.value, 1)
                expectation.fulfill() // Fulfill when state is updated to value 1
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
                XCTAssertEqual(newValue, 1)
                expectation.fulfill() // Fulfill when value is updated to 1
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
        store.subscribe(\.user)
            .sink { [self] newValue in
                XCTAssertEqual(newValue?.username, testUserName)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        // Dispatch increment action
        store.dispatch(TestAction.user(testUserName))
        // Wait for the state path change to be triggered
        wait(for: [expectation], timeout: 0.5)
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
        let expectation = expectation(description: #function)
        XCTAssertNil(store.getState())
        var actionCounter = 0
        store.subscribe { state in
            switch actionCounter {
            case 0:
                XCTAssertNotNil(state)
                XCTAssertNil(state?.name)
                actionCounter += 1
            case 1:
                XCTAssertEqual(state?.name, "test")
                expectation.fulfill()
            default:
                XCTFail("Unexpected state update")
            }
        }.store(in: &cancellables)

        store.dispatch(SomeAction(name: nil))
        store.dispatch(SomeAction(name: "test"))
        wait(for: [expectation], timeout: 10)
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
            middlewares: [incrementMiddleware, decrementMiddleware, noChangeMiddleware, validateMiddleware],
            reducer: mockReducer
        )
    }

    override func tearDown() {
        // Reset the store and cancellables after each test
        cancellables.removeAll()
        store = nil
        super.tearDown()
    }

    func testMiddlewareIncrement() {
        let expectation = self.expectation(description: #function)
        store.subscribe(path: \.value) { value in
            XCTAssertEqual(value, 1)
            expectation.fulfill()
        }.store(in: &cancellables)
        store.dispatch(TestAction.increment)
        wait(for: [expectation])
    }

    func testMiddlewareDecrement() {
        let expectation = self.expectation(description: #function)
        store.subscribe(path: \.value) { value in
            XCTAssertEqual(value, 1)
            expectation.fulfill()
        }.store(in: &cancellables)
        store.dispatch(TestAction.decrement)
        wait(for: [expectation])
    }

    func testMiddlewareNoChange() {
        let expectation = self.expectation(description: "State type should be updated")
        XCTAssertEqual(store.getState().value, 0)
        store.subscribe(path: \.value)
            .dropFirst()
            .sink { value in
                XCTAssertEqual(value, 5)
                XCTAssertEqual(self.store.getState().value, 5)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        store.dispatch(TestAction.noChange)
        wait(for: [expectation], timeout: 0.5)
    }

    // MARK: - Mock middleware

    fileprivate let incrementMiddleware: ReduxMiddleware<TestState> = { _, dispatch in
        let handler: ReduxActionDispatch = { action in
            dispatch(action)
        }
        return handler
    }

    // MARK: - Mock middleware

    fileprivate let decrementMiddleware: ReduxMiddleware<TestState> = { _, dispatch in
        let handler: ReduxActionDispatch = { action in
            // change current action to new action synchronously
            if (action as? TestAction) == .decrement {
                dispatch(TestAction.increment)
            } else {
                dispatch(action)
            }
        }
        return handler
    }

    fileprivate let noChangeMiddleware: ReduxMiddleware<TestState> = { store, dispatch in
        let handler: ReduxActionDispatch = { action in
            // change current action to new action synchronously and continew current action
            if (action as? TestAction) == .noChange {
                store.dispatchAsync(TestAction.update(5))
            }
            dispatch(action)
        }
        return handler
    }

    fileprivate let validateMiddleware: ReduxMiddleware<TestState> = { store, dispatch in
        let handler: ReduxActionDispatch = { action in
            guard let action = action as? TestAction else {
                preconditionFailure("Invalid action type")
            }
            // XCTAssertTrue([TestAction.increment, .noChange, .update(5)].contains(action))
            XCTAssertNotNil(store.getState())
            dispatch(action)
        }
        return handler
    }
}

// MARK: -

final class ReduxConcurrencyTests: XCTestCase, @unchecked Sendable {
    private var redux: Redux<TestState>!
    var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        let reducer: ReduxReducer<TestState> = { action, state in
            switch action as? TestAction {
            case .increment:
                return TestState(value: state.value + 1)
            default:
                return state
            }
        }
        redux = Redux(state: TestState(value: 0), reducer: reducer)
    }

    func testConcurrentDispatch() {
        let expectation = XCTestExpectation(description: "Concurrent dispatches complete")

        // Dispatch IncrementAction 1000 times concurrently
        DispatchQueue.concurrentPerform(iterations: 1000) { _ in
            self.redux.dispatch(TestAction.increment)
        }

        // Give some time for all async dispatches to complete
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            // Check final state count should be 1000
            XCTAssertEqual(self.redux.getState().value, 1000)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 3.0)
    }

    func testSubscribeReceivesUpdates() {
        let count = 100
        let expectation = XCTestExpectation(description: "Subscriber receives state updates")
        var receivedCounts = [Int]()
        redux.subscribe { [self] state in
            receivedCounts.append(state.value)
            _ = redux.getState()
            XCTAssertEqual(receivedCounts, Array(1 ... state.value))
            if state.value == count {
                expectation.fulfill()
            }
        }
        .store(in: &cancellables)

        DispatchQueue.concurrentPerform(iterations: count) { _ in
            self.redux.dispatch(TestAction.increment)
        }
        wait(for: [expectation])
    }

    func testConcurrentReadsAndWrites() {
        let dispatchGroup = DispatchGroup()

        redux.subscribe(path: \.value) { _ in
            dispatchGroup.leave()
        }.store(in: &cancellables)

        for _ in 1 ... 500 {
            dispatchGroup.enter()
            DispatchQueue.global().async {
                self.redux.dispatch(TestAction.increment)
            }
            dispatchGroup.enter()
            DispatchQueue.global().async {
                _ = self.redux.getState()
                dispatchGroup.leave()
            }
        }

        let expectation = XCTestExpectation(description: "Concurrent reads and writes complete")

        dispatchGroup.notify(queue: .main) {
            // Expect count to be 500 (all increments)
            XCTAssertEqual(self.redux.getState().value, 500)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 3.0)
    }
}
