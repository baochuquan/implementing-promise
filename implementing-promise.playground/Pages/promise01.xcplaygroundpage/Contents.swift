import UIKit
import Darwin
import CFNetwork

enum State {
    case pending
    case fulfilled
    case rejected
}

class Promise<T> {
    typealias Resolve<T> = (T) -> Void
    typealias Reject = (Error) -> Void
    typealias Executor = (_ resolve: @escaping Resolve<T>, _ reject: @escaping Reject) -> Void

    private(set) var state: State = .pending {
        didSet {
            // 清理 resolve 和 reject，消除循环引用
            onFulfilledCallbacks = []
            onRejectedCallbacks = []
        }
    }
    private(set) var value: T?
    private(set) var error: Error?

    private(set) var onFulfilledCallbacks = [Resolve<T>]()
    private(set) var onRejectedCallbacks = [Reject]()

    init(_ executor: Executor) {
        // resolve 和 reject 必须强引用 self，避免在执行 resolve 和 reject 之前系统释放 self
        let resolve: Resolve<T> = { value in
            self.value = value
            self.onFulfilledCallbacks.forEach { onFullfilled in
                onFullfilled(value)
            }
            self.state = .fulfilled
        }
        let reject: Reject = { error in
            self.error = error
            self.onRejectedCallbacks.forEach { onRejected in
                onRejected(error)
            }
            self.state = .rejected
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
    // Functor
    @discardableResult
    func then<R>(onFulfilled: @escaping (T) -> R, onRejected: @escaping (Error) -> Void) -> Promise<R> {
        switch state {
        case .pending:
            // 将普通函数应用到包装类型，并返回包装类型
            return Promise<R> { [weak self] resolve, reject in
                // 初始化时即执行
                // 在 curr promise 加入 onFulfilled/onRejected 任务，任务可修改 curr promise 的状态
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
            // 将普通函数应用到包装类型，并返回包装类型
            return Promise<R> { resolve, _ in
                let r = onFulfilled(value)
                resolve(r)
            }
        case .rejected:
            let error = error!
            // 将普通函数应用到包装类型，并返回包装类型
            return Promise<R> { _, reject in
                onRejected(error)
                reject(error)
            }

        }
    }

    // Monad
    @discardableResult
    func then<R>(onFulfilled: @escaping (T) -> Promise<R>, onRejected: @escaping (Error) -> Void) -> Promise<R> {
        switch state {
        case .pending:
            return Promise<R> { [weak self] resolve, reject in
                // 初始化时即执行
                // 在 prev promise 的 callback 队列加入一个生成 midd promise 的任务。
                // 在 midd promise 的 callback 队列加入一个任务，修改 curr promise 状态。
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
}

/// convenient Then
extension Promise {
    // Functor
    func then<R>(onFulfilled: @escaping (T) -> R) -> Promise<R> {
        return then(onFulfilled: onFulfilled, onRejected: { _ in })
    }

    // Monad
    func then<R>(onFullfilled: @escaping (T) -> Promise<R>) -> Promise<R> {
        return then(onFulfilled: onFullfilled, onRejected: { _ in })
    }
}

/// Additional
extension Promise {
    func `catch`(onError: @escaping (Error) -> Void) -> Promise<Void> {
        return then(onFulfilled: { _ in }, onRejected: onError)
    }

    func done(onNext: @escaping (T) -> Void) -> Promise<Void> {
        return then(onFulfilled: onNext)
    }

    func finally(onCompleted: @escaping () -> Void) -> Void {
        then(onFulfilled: { _ in onCompleted() }, onRejected: { _ in onCompleted() })
    }
}

/// Syntactic Sugar
func firstly<T>(closure: @escaping () -> Promise<T>) -> Promise<T> {
    return closure()
}




/// Test
enum NetworkError: Error {
    case decodeError
    case responseError
}

struct User {
    let name: String
    let avatarURL: String

    var description: String { "name: => \(name); avatar => \(avatarURL)" }
}

class TestAPI {
    func user() -> Promise<User> {
        return Promise<User> { (resolve, reject) in
            // Mock HTTP Request
            print("request user info")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                let result = arc4random() % 10 == 0
                if result {
                    let user = User(name: "chuquan", avatarURL: "avatarurl")
                    resolve(user)
                } else {
                    reject(NetworkError.responseError)
                }
            }
        }
    }

    func avatar() -> Promise<UIImage> {
        return Promise<UIImage> { (resolve, reject) in
            // Mock HTTP Request
            print("request avatar info")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                let result = arc4random() % 10 != 0
                if result {
                    let avatar = UIImage()
                    resolve(avatar)
                } else {
                    reject(NetworkError.decodeError)
                }
            }
        }
    }
}

print("============ test 01 ============")
let api = TestAPI()
firstly {
    api.user()
}.then { user in
    print("user name => \(user)")
    api.avatar()
}.catch { _ in
    print("request error")
}.finally {
    print("request complete")
}

print("============ test 02 ============")
firstly {
    Promise<Int> { resolve, reject in
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            resolve(1)
        }
    }
}.then { v in
    return v * 2
}.then { v in
    return "string: \(v)"
}.done { str in
    print(str)
}
