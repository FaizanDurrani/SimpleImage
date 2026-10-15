import Foundation
import SimpleImage
import UIKit

private enum AssociatedKeys {
  nonisolated(unsafe) static var currentTask = true
  nonisolated(unsafe) static var requestID = true
}

/// Adopted by `UIImageView` subclasses that render image types other than `UIImage`,
/// such as animated images.
@MainActor
public protocol SimpleImageDisplaying: UIImageView {
  func si_display(_ image: any ProcessedImage)
  
  /// Called before a new image is requested, e.g. to stop a running animation.
  func si_prepareForNewImage()
}

extension SimpleImageDisplaying {
  public func si_prepareForNewImage() {}
}

@MainActor
extension UIImageView {
  public private(set) var si_currentTask: SimpleImageTask? {
    get { objc_getAssociatedObject(self, &AssociatedKeys.currentTask) as? SimpleImageTask }
    set { objc_setAssociatedObject(self, &AssociatedKeys.currentTask, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
  }

  private var si_requestID: UUID? {
    get { objc_getAssociatedObject(self, &AssociatedKeys.requestID) as? UUID }
    set { objc_setAssociatedObject(self, &AssociatedKeys.requestID, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
  }

  public func si_cancelImageDownload() {
    si_requestID = nil
    si_currentTask?.cancel()
    si_currentTask = nil
  }

  public func si_setImage(
    using imageManager: SimpleImageManager,
    request: URLRequest,
    processors: [any SimpleImageProcessor] = [],
    placeholderImage: UIImage? = nil
  ) {
    si_cancelImageDownload()
    (self as? SimpleImageDisplaying)?.si_prepareForNewImage()
    
    if let cachedImage = imageManager.cachedImage(request: request, processors: processors) {
      si_render(cachedImage)
      return
    }
    
    image = placeholderImage
    let requestID = UUID()
    si_requestID = requestID
    si_currentTask = imageManager.retrieveImage(request: request, processors: processors) { [weak self] result in
      guard let self, self.si_requestID == requestID else { return }
      self.si_currentTask = nil
      if case .success(let image) = result { self.si_render(image) }
    }
  }
  
  private func si_render(_ image: any ProcessedImage) {
    if let displaying = self as? SimpleImageDisplaying {
      displaying.si_display(image)
    } else if let image = image as? UIImageConvertible {
      self.image = image.uiImage
    }
  }
}
