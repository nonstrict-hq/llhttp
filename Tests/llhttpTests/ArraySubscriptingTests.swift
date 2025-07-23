import Testing
import Foundation
@testable import llhttp

@Suite("Array Position Subscript")
struct ArraySubscriptingTests {
    
    // MARK: - Empty Array Tests
    
    @Test("Empty array getter returns nil for any position", 
          arguments: [Position.first, .last])
    func testEmptyArrayGetterReturnsNil(position: Position) {
        let emptyArray: [Int] = []
        #expect(emptyArray[position] == nil)
    }
    
    @Test("Empty array setter does nothing", 
          arguments: [Position.first, .last])
    func testEmptyArraySetterDoesNothing(position: Position) {
        var emptyArray: [Int] = []
        emptyArray[position] = 42
        #expect(emptyArray.isEmpty)
    }
    
    // MARK: - Single Element Array Tests
    
    @Test("Single element array getter returns same element for both positions",
          arguments: [Position.first, .last])
    func testSingleElementArrayGetter(position: Position) {
        let singleElementArray = [42]
        #expect(singleElementArray[position] == 42)
    }
    
    @Test("Single element array setter updates the element for both positions")
    func testSingleElementArraySetter() {
        var array = [10]
        
        // Test setting via .first position
        array[.first] = 20
        #expect(array == [20])
        
        // Test setting via .last position
        array[.last] = 30
        #expect(array == [30])
    }
    
    // MARK: - Multi-Element Array Tests
    
    @Test("Multi-element array getter returns correct elements",
          arguments: zip([2, 3, 5, 10], [Position.first, .last, .first, .last]))
    func testMultiElementArrayGetter(size: Int, position: Position) {
        let array = Array(1...size)
        let expected = position == .first ? 1 : size
        #expect(array[position] == expected)
    }
    
    @Test("Multi-element array setter updates only targeted position")
    func testMultiElementArraySetter() {
        var array = [1, 2, 3, 4, 5]
        
        // Test setting first element
        array[.first] = 10
        #expect(array == [10, 2, 3, 4, 5])
        
        // Test setting last element
        array[.last] = 50
        #expect(array == [10, 2, 3, 4, 50])
        
        // Verify middle elements unchanged
        #expect(array[1] == 2)
        #expect(array[2] == 3)
        #expect(array[3] == 4)
    }
    
    // MARK: - In-Place Mutation Tests
    
    @Test("In-place mutation of reference types")
    func testReferenceTypeMutation() {
        class Counter {
            var value: Int
            init(_ value: Int) { self.value = value }
        }
        
        let array = [Counter(1), Counter(2), Counter(3)]
        
        // Mutate first element
        array[.first]?.value = 10
        #expect(array[0].value == 10)
        
        // Mutate last element
        array[.last]?.value = 30
        #expect(array[2].value == 30)
        
        // Verify middle element unchanged
        #expect(array[1].value == 2)
    }
    
    @Test("In-place mutation with value types")
    func testValueTypeMutation() {
        // Use Array of Arrays (value type) that supports in-place mutation
        var array = [[1, 2], [3, 4], [5, 6]]
        
        // Use one-liner optional chaining with custom subscript
        array[.first]?.append(99)
        array[.last]?.removeFirst()
        
        #expect(array[0] == [1, 2, 99])
        #expect(array[2] == [6])
        #expect(array[1] == [3, 4]) // unchanged
    }
    
    @Test("In-place mutation with mutable struct")
    func testMutableStructMutation() {
        struct MutablePoint {
            var x: Int
            var y: Int
            
            mutating func moveBy(dx: Int, dy: Int) {
                x += dx
                y += dy
            }
        }
        
        var array = [MutablePoint(x: 0, y: 0), MutablePoint(x: 1, y: 1), MutablePoint(x: 2, y: 2)]
        
        // Use one-liner optional chaining with custom subscript
        array[.first]?.moveBy(dx: 10, dy: 10)
        array[.last]?.moveBy(dx: 20, dy: 20)
        
        #expect(array[0].x == 10)
        #expect(array[0].y == 10)
        #expect(array[2].x == 22)
        #expect(array[2].y == 22)
        #expect(array[1].x == 1) // unchanged
        #expect(array[1].y == 1) // unchanged
    }
    
    // MARK: - Nil Setter Tests
    
    @Test("Setting nil does nothing to array",
          arguments: [Position.first, Position.last])
    func testNilSetterDoesNothing(position: Position) {
        var array = [1, 2, 3]
        let originalArray = array
        
        array[position] = nil
        #expect(array == originalArray)
    }
    
    @Test("Setting nil on single element array does nothing")
    func testNilSetterOnSingleElement() {
        var array = [42]
        
        array[.first] = nil
        #expect(array == [42])
        
        array[.last] = nil
        #expect(array == [42])
    }
    
    // MARK: - Generic Type Tests
    
    @Test("Works with different array types")
    func testDifferentGenericTypes() {
        // Test with String array
        var stringArray = ["apple", "banana", "cherry"]
        #expect(stringArray[.first] == "apple")
        #expect(stringArray[.last] == "cherry")
        
        stringArray[.first] = "apricot"
        #expect(stringArray[0] == "apricot")
        
        // Test with Double array
        var doubleArray = [1.1, 2.2, 3.3]
        #expect(doubleArray[.first] == 1.1)
        #expect(doubleArray[.last] == 3.3)
        
        doubleArray[.last] = 4.4
        #expect(doubleArray[2] == 4.4)
        
        // Test with optional array
        var optionalArray: [Int?] = [1, nil, 3]
        #expect(optionalArray[.first] == 1)
        #expect(optionalArray[.last] == 3)
        
        // Setting nil does nothing (due to guard let newValue in setter)
        optionalArray[.first] = nil
        #expect(optionalArray[0] == 1) // Value unchanged
        #expect(optionalArray.count == 3) // Array length unchanged
    }
    
    @Test("Works with custom types")
    func testCustomTypes() {
        struct Person {
            let name: String
            let age: Int
        }
        
        var people = [
            Person(name: "Alice", age: 25),
            Person(name: "Bob", age: 30),
            Person(name: "Charlie", age: 35)
        ]
        
        // Test getter
        #expect(people[.first]?.name == "Alice")
        #expect(people[.last]?.name == "Charlie")
        
        // Test setter
        people[.first] = Person(name: "Anna", age: 26)
        #expect(people[0].name == "Anna")
        #expect(people[0].age == 26)
        
        people[.last] = Person(name: "Carol", age: 36)
        #expect(people[2].name == "Carol")
        #expect(people[2].age == 36)
        
        // Verify middle element unchanged
        #expect(people[1].name == "Bob")
        #expect(people[1].age == 30)
    }
    
}
