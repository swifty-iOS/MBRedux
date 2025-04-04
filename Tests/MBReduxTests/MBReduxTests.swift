import XCTest
import Combine
@testable import MBRedux

// Define a simple test state and action
private struct TestState: StateType {
    var value: Int
}

private enum TestAction: ReduxAction {
    case increment
    case decrement
    case noChange
}

private enum MockReducer {
    static func reduce(action: ReduxAction, state: TestState?) -> TestState? {
        switch action {
        case TestAction.increment:
            return TestState(value: (state?.value ?? 0) + 1)
        case TestAction.decrement:
            return TestState(value: (state?.value ?? 0) - 1)
        default:
            return state
        }
    }
}

final class ReduxStoreTests: XCTestCase {
    
    // The Redux store instance to test
    private var store: Redux<TestState>!
    
    // The cancellables to hold subscriptions
    var cancellables: Set<AnyCancellable> = []
    
    override func setUp() {
        super.setUp()
        // Initialize the store with an initial state
        store = Redux<TestState>()
    }
    
    override func tearDown() {
        // Reset the store and cancellables after each test
        cancellables.removeAll()
        store = nil
        super.tearDown()
    }
    
    func testReducerRegistration() {
        // Try registering the reducer
        XCTAssertNoThrow(try store.register(reducer: MockReducer.reduce))
        // Try to register the same reducer again, should throw error
        XCTAssertThrowsError(try store.register(reducer: MockReducer.reduce)) { error in
            XCTAssertEqual((error as NSError).domain, "ReduxError.reducerAlreadyRegistered")
        }
    }
    
    func testDispatchAction() throws {
        // Register the reducer
        try store.register(reducer: MockReducer.reduce)
        // Dispatch actions
        store.dispatch(TestAction.increment)
        store.dispatch(TestAction.increment)
        // Check the state after dispatching
        store.subscribe()
            .sink { newState in
                XCTAssertEqual(newState?.value, 2) // We dispatched increment twice
            }
            .store(in: &cancellables)
        
    }
    
    @MainActor
    func testStateSubscription() throws {
        // Register the reducer
        try store.register(reducer: MockReducer.reduce)
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
    func testStatePathSubscription() throws {
        // Register the reducer
        try store.register(reducer: MockReducer.reduce)
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
    
    // If this fails adjust timout
    @MainActor
    func testNoStateChange() throws {
        // Register the reducer
        try store.register(reducer: MockReducer.reduce)
        // Expectation for state path change subscription
        let expectation = self.expectation(description: "State change should not be call")
        // Create default state
        store.subscribe().sink { state in
            XCTAssertNotNil(state)
        }.store(in: &cancellables)
        store.dispatch(TestAction.increment)
        // Check for flag if subscriber calls
        var isUpdateCalled = false
        store.subscribe(path: \.value)
            .sink { newState in
                isUpdateCalled = true
            }
            .store(in: &cancellables)
        // dispach no action
        store.dispatch(TestAction.noChange)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertFalse(isUpdateCalled)
            expectation.fulfill()
        }
        // Wait for both before and after state update expectations
        wait(for: [expectation], timeout: 1)
    }
    
    func testState() throws {
        XCTAssertNil(store.getState())
        XCTAssertNil(store.getState(path: \.value))
        // Register the reducer
        try store.register(reducer: MockReducer.reduce)
        // Expectation for state path change subscription
        // Create default state
        store.dispatch(TestAction.increment)
        XCTAssertNotNil(store.getState())
        XCTAssertEqual(store.getState(path: \.value), 1)
    }
    
}
