//
//  SimpleImageSharedTask.swift
//  SimpleImage
//
//  Created by Faizan Durrani on 29/08/2026.
//


import Foundation

enum SimpleImageStageOutput: Sendable {
  case raw(RawImage, isFromDiskCache: Bool)
  case image(any ProcessedImage)
}

class SimpleImageSharedTask: @unchecked Sendable {
  enum State {
    case waiting(work: @isolated(any) @Sendable () async -> Void)
    case working(Task<Void, Never>)
    case finished(result: Result<SimpleImageStageOutput, Error>)
    case cancelled
  }
  
  let request: URLRequest
  var isCancelled: Bool {
    self.lock.withLock {
      if case .cancelled = state { return true }
      return false
    }
  }
  
  nonisolated(unsafe) var state: State!
  private nonisolated(unsafe) var children: [UUID: SimpleImageTask]
  
  private let lock = NSLock()
  private let onFinish: @Sendable (SimpleImageSharedTask) -> Void
  
  init(
    request: URLRequest,
    onFinish: @escaping @Sendable (SimpleImageSharedTask) -> Void,
  ) {
    self.children = [:]
    self.request = request
    self.onFinish = onFinish
  }
  
  enum AttachResult {
    case attached
    case finished(Result<SimpleImageStageOutput, Error>)
    case cancelled
  }

  func attach(task: SimpleImageTask) -> AttachResult {
    self.lock.withLock {
      switch self.state! {
        case .waiting(work: let work):
          self.children[task.id] = task
          // Started from the main thread; don't inherit its priority and compete with scrolling.
          self.state = .working(Task(priority: .medium, operation: work))
          return .attached
          
        case .working:
          self.children[task.id] = task
          return .attached

        case .finished(let result):
          return .finished(result)

        case .cancelled:
          return .cancelled
      }
    }
  }
  
  func detach(task: SimpleImageTask) {
    var underlyingTask: Task<Void, Never>?
    var didCancel = false

    self.lock.withLock {
      self.children.removeValue(forKey: task.id)

      guard self.children.isEmpty else { return }

      switch self.state! {
        case .waiting:
          self.state = .cancelled
          didCancel = true

        case .working(let task):
          self.state = .cancelled
          underlyingTask = task
          didCancel = true

        case .finished, .cancelled:
          break
      }
    }

    guard didCancel else { return }

    underlyingTask?.cancel()
    self.onFinish(self)
  }
  
  func reportProgress(_ fraction: Double) {
    let subscribers = lock.withLock { Array(children.values) }
    subscribers.forEach { $0.reportProgress(fraction) }
  }

  func finish(with result: Result<SimpleImageStageOutput, Error>) {
    self.lock.lock()
    guard case .working = self.state else {
      self.lock.unlock()
      return
    }
    
    let children = self.children
    self.state = .finished(result: result)
    self.children.removeAll()
    
    self.lock.unlock()
    
    self.onFinish(self)
    for (_, child) in children {
      child.processStageResult(result, from: self)
    }
  }
}

/// Coalesces shared tasks by key until they finish or are cancelled.
final class SimpleImageSharedTaskRegistry<SharedTask: SimpleImageSharedTask>: @unchecked Sendable {
  private let lock = NSLock()
  private var tasks: [String: SharedTask] = [:]
  
  func task(
    forKey key: String,
    make: (_ onFinish: @escaping @Sendable (SimpleImageSharedTask) -> Void) -> SharedTask
  ) -> SharedTask {
    self.lock.withLock {
      if let task = self.tasks[key], !task.isCancelled {
        return task
      }
      
      let task = make { [weak self] finishedTask in
        self?.removeTask(finishedTask, forKey: key)
      }
      
      self.tasks[key] = task
      return task
    }
  }
  
  private func removeTask(_ task: SimpleImageSharedTask, forKey key: String) {
    self.lock.withLock {
      if self.tasks[key] === task {
        self.tasks.removeValue(forKey: key)
      }
    }
  }
}
