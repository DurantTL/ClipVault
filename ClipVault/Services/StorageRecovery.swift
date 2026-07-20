import Darwin
import Foundation

enum StorageFailureKind: Equatable {
  case outOfSpace
  case permissionLost
  case readOnly
  case unavailable
  case other
}

enum StorageRecoveryOperation {
  case ingest
  case resumeIngest
  case backup
  case projectSave
  case export
}

/// Turns low-level Cocoa/POSIX storage failures into instructions a person can
/// act on. File-system errors often wrap the useful POSIX error, so classification
/// walks the underlying-error chain before falling back to the original text.
enum StorageRecovery {
  static func classify(_ error: Error) -> StorageFailureKind {
    let errors = errorChain(startingAt: error)

    if errors.contains(where: isOutOfSpace) { return .outOfSpace }
    if errors.contains(where: isReadOnly) { return .readOnly }
    if errors.contains(where: isPermissionFailure) { return .permissionLost }
    if errors.contains(where: isUnavailable) { return .unavailable }
    return .other
  }

  static func message(for error: Error, operation: StorageRecoveryOperation) -> String {
    switch (operation, classify(error)) {
    case (.ingest, .outOfSpace), (.resumeIngest, .outOfSpace):
      return "The destination is out of space. Free space on that drive, then resume the ingest. The partial copy was kept and the source media was not changed."
    case (.ingest, .permissionLost), (.resumeIngest, .permissionLost):
      return "Access to the source or destination was lost. Reconnect the drive and grant access again, then resume the ingest. The source media was not changed."
    case (.ingest, .readOnly), (.resumeIngest, .readOnly):
      return "The destination is read-only. Choose a writable destination or correct its permissions, then resume the ingest. The source media was not changed."
    case (.ingest, .unavailable), (.resumeIngest, .unavailable):
      return "A source, destination, or network volume became unavailable. Reconnect or remount it, then resume the ingest. The last safe project checkpoint and any partial copy were kept."

    case (.backup, .outOfSpace):
      return "The backup destination is out of space. The primary copy remains verified, but this backup was not completed."
    case (.backup, .permissionLost):
      return "Access to the backup destination was lost. The primary copy remains verified, but this backup was not completed."
    case (.backup, .readOnly):
      return "The backup destination is read-only. The primary copy remains verified, but this backup was not completed."
    case (.backup, .unavailable):
      return "The backup destination became unavailable. The primary copy remains verified, but this backup was not completed."

    case (.projectSave, .outOfSpace):
      return "Project changes could not be saved because the project drive is out of space. Free space, then retry the project save. The changes are still open in memory but are not safely stored yet."
    case (.projectSave, .permissionLost):
      return "Project changes could not be saved because access to the project folder was lost. Reconnect the drive or grant access again, then retry the project save."
    case (.projectSave, .readOnly):
      return "Project changes could not be saved because the project folder is read-only. Correct its permissions, then retry the project save."
    case (.projectSave, .unavailable):
      return "Project changes could not be saved because the project drive or network volume is unavailable. Reconnect or remount it, then retry the project save."

    case (.export, .outOfSpace):
      return "The export destination is out of space. Free space or choose another folder, then export again. No project or source media was changed."
    case (.export, .permissionLost):
      return "The export could not be written because access to the destination was lost. Grant access again or choose another folder. No project or source media was changed."
    case (.export, .readOnly):
      return "The export destination is read-only. Choose a writable folder and export again. No project or source media was changed."
    case (.export, .unavailable):
      return "The export destination became unavailable. Reconnect or remount it, then export again. No project or source media was changed."

    case (.ingest, .other):
      return "Ingest could not continue: \(error.localizedDescription). The project remains reopenable and the source media was not changed."
    case (.resumeIngest, .other):
      return "Ingest could not resume: \(error.localizedDescription). Reconnect the source and destination, then try again."
    case (.backup, .other):
      return "The backup could not be completed: \(error.localizedDescription). The primary copy remains verified."
    case (.projectSave, .other):
      return "Project changes could not be saved: \(error.localizedDescription). Retry the project save before closing the project."
    case (.export, .other):
      return "The export could not be written: \(error.localizedDescription). No project or source media was changed."
    }
  }

  private static func errorChain(startingAt error: Error) -> [NSError] {
    var result: [NSError] = []
    var next: NSError? = error as NSError
    var visited = Set<ObjectIdentifier>()

    while let current = next {
      let identifier = ObjectIdentifier(current)
      guard visited.insert(identifier).inserted else { break }
      result.append(current)
      next = current.userInfo[NSUnderlyingErrorKey] as? NSError
    }
    return result
  }

  private static func isOutOfSpace(_ error: NSError) -> Bool {
    (error.domain == NSCocoaErrorDomain && error.code == CocoaError.Code.fileWriteOutOfSpace.rawValue)
      || (error.domain == NSPOSIXErrorDomain && (Int32(error.code) == ENOSPC || Int32(error.code) == EDQUOT))
  }

  private static func isPermissionFailure(_ error: NSError) -> Bool {
    let cocoaCodes = [
      CocoaError.Code.fileReadNoPermission.rawValue,
      CocoaError.Code.fileWriteNoPermission.rawValue,
    ]
    return (error.domain == NSCocoaErrorDomain && cocoaCodes.contains(error.code))
      || (error.domain == NSPOSIXErrorDomain && (Int32(error.code) == EACCES || Int32(error.code) == EPERM))
  }

  private static func isReadOnly(_ error: NSError) -> Bool {
    (error.domain == NSCocoaErrorDomain && error.code == CocoaError.Code.fileWriteVolumeReadOnly.rawValue)
      || (error.domain == NSPOSIXErrorDomain && Int32(error.code) == EROFS)
  }

  private static func isUnavailable(_ error: NSError) -> Bool {
    let cocoaCodes = [
      CocoaError.Code.fileNoSuchFile.rawValue,
      CocoaError.Code.fileReadNoSuchFile.rawValue,
    ]
    let posixCodes = [ENOENT, EIO, ENXIO, ENODEV, ESTALE, ETIMEDOUT, ENETDOWN, ENETUNREACH, ECONNRESET]
    return (error.domain == NSCocoaErrorDomain && cocoaCodes.contains(error.code))
      || (error.domain == NSPOSIXErrorDomain && posixCodes.contains(Int32(error.code)))
  }
}
