//
//  Event.swift
//  webview
//
//  Created by 차순혁 on 2/4/26.
//

import Combine

/// 일회성 이벤트를 위한 Property Wrapper
/// - @Published와 동일한 문법으로 사용 가능
/// - 내부적으로 PassthroughSubject를 사용하여 값을 보관하지 않음
/// - 값 읽기 불가 (write-only)
@propertyWrapper
public struct Event<Value> {
    private let subject = PassthroughSubject<Value, Never>()

    public var wrappedValue: Value {
        get { fatalError("@Event is write-only. Use $property to subscribe.") }
        set { subject.send(newValue) }
    }

    public var projectedValue: AnyPublisher<Value, Never> {
        subject.eraseToAnyPublisher()
    }

    public init() {}
}
