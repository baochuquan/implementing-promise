import UIKit

enum State {
    case pending
    case fulfilled
    case rejected
}

class Promise<T> {
    typealias OnFulfilled<T> = (T) -> Void
    typealias OnRejected = (Error) -> Void
    typealias Resolve<T> = (T) -> Void
    typealias Reject = (Error) -> Void
    typealias Executor = (_ resolve: @escaping Resolve<T>, _ reject: @escaping Reject) -> Void

    private(set) var state: State = .pending
    private(set) var value: T?
    private(set) var error: Error?

    private(set) var onFulfilledCallbacks = [OnFulfilled<T>]()
    private(set) var onRejectedCallbacks = [OnRejected]()

    init(_ executor: Executor) {
        let resolve: Resolve<T> = { [weak self] value in
            self?.value = value
            self?.state = .fulfilled
            self?.onFulfilledCallbacks.forEach { onFullfilled in
                onFullfilled(value)
            }

        }
        let reject: Reject = { [weak self] error in
            self?.error = error
            self?.state = .rejected
            self?.onRejectedCallbacks.forEach { onRejected in
                onRejected(error)
            }
        }
        executor { value in
            resolve(value)
        } _: { error in
            reject(error)
        }
    }
}

/// Channing Core
extension Promise {
    func then<R>(onFulfilled: @escaping (T) -> Promise<R>, onRejected: @escaping (Error) -> Void) -> Promise<R> {
        switch state {
        case .pending:
            return Promise<R> { [weak self] resolve, reject in
                self?.onFulfilledCallbacks.append { value in
                    let promise = onFulfilled(value)
                    promise.then(onFulfilled: { r in
                        resolve(r)
                    }, onRejected: { _ in })
                }
                self?.onRejectedCallbacks.append { error in
                    onRejected(error)
                    reject(error)
                }
            }
        case .fulfilled:
            return onFulfilled(value!)
        case .rejected:
            return Promise<R> { _, reject in
                onRejected(error!)
                reject(error!)
            }
        }
    }

    func then<R>(onFulfilled: @escaping (T) -> R, onRejected: @escaping (Error) -> Void) -> Promise<R> {
        switch state {
        case .pending:
            return Promise<R> { [weak self] resolve, reject in
                self?.onFulfilledCallbacks.append { value in
                    let r = onFulfilled(value)
                    resolve(r)
                }
                self?.onRejectedCallbacks.append { error in
                    onRejected(error)
                    reject(error)
                }
            }

        case .fulfilled:
            let value = value!
            return Promise<R> { resolve, _ in
                let r = onFulfilled(value)
                resolve(r)
            }
        case .rejected:
            let error = error!
            return Promise<R> { _, reject in
                onRejected(error)
                reject(error)
            }

        }
    }
}

/// Convienent Then
extension Promise {
    func then<R>(onFulfilled: @escaping (T) -> R) -> Promise<R> {
        return then(onFulfilled: onFulfilled, onRejected: { _ in })
    }

    func then<R>(onFullfilled: @escaping (T) -> Promise<R>) -> Promise<R> {
        return then(onFulfilled: onFullfilled, onRejected: { _ in })
    }
}

/// Additional
extension Promise {
    func `catch`(onError: @escaping (Error) -> Void) -> Promise<Void> {
        return then(onFulfilled: { _ in }, onRejected: onError)
    }

    func finally(onCompleted: @escaping () -> Void) -> Promise<Void> {
        return then(onFulfilled: { _ in onCompleted() }, onRejected: { _ in onCompleted() })
    }

    func done(onNext: @escaping (T) -> Void) -> Promise<Void> {
        return then(onFulfilled: onNext)
    }
}

/// Syntactic Sugar
func firstly<T>(closure: @escaping () -> Promise<T>) -> Promise<T> {
    return closure()
}

let p1 = Promise<Int> { (resolve, reject) in
    resolve(1)
}

p1.then { v in
    print("HHHH: v => \(v)")
} onRejected: { _ in
    print("HHHH: error")
}

