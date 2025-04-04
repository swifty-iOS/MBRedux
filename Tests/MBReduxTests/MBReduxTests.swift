// The Swift Programming Language
// https://docs.swift.org/swift-book
//
// Created by Manish on 03/04/25.
//

import XCTest
import Combine
@testable import MBRedux

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


private enum TestAction: ReduxAction {
    case increment
    case decrement
    case noChange
    case user(String)
}

private func mockReducer(action: ReduxAction, state: TestState?) -> TestState? {
   
    switch action {
    case TestAction.increment:
        return TestState(value: (state?.value ?? 0) + 1, user: state?.user)
    case TestAction.decrement:
        return TestState(value: (state?.value ?? 0) - 1, user: state?.user)
    case TestAction.user(let username):
        let newState = state ?? TestState(value: 0)
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
        store = Redux<TestState>(reducer: mockReducer)
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
        XCTAssertEqual(store.getState()?.value, 2)
        XCTAssertEqual(store.getState(path: \.value), 2)
    }
    
    @MainActor
    func testStateSubscription() {
        // Expectation for state change subscription
        let expectation = expectation(description: "State should be updated")
        store.subscribe()
            .sink { newState in
                if newState?.value == 1 {
                    expectation.fulfill() // Fulfill when state is updated to value 1
                }
            }
            .store(in: &cancellables)
        
        // Dispatch increment action
        store.dispatch(TestAction.increment)
        
        // Wait for the state change to be triggered
        wait(for: [expectation], timeout: 0.5)
    }
    
    @MainActor
    func testStatePathSubscription() {
        // Expectation for state path change subscription
        let expectation = self.expectation(description: "State path value should be updated")
        store.subscribe(path: \TestState.value)
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
    
    @MainActor
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
    
    // If this fails adjust timout
    @MainActor
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertFalse(isUpdateCalled)
            expectation.fulfill()
        }
        // Wait for both before and after state update expectations
        wait(for: [expectation], timeout: 1)
    }
    
}
