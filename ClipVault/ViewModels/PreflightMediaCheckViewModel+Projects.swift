import Foundation

extension PreflightMediaCheckViewModel {
  func projectCandidates(
    from projects: [ClipVaultProject]
  ) -> [PreflightCandidate] {
    var candidates: [PreflightCandidate] = []

    for project in projects {
      for clip in project.clips {
        guard clip.copyStatus == .copied || clip.verificationStatus == .verified else {
          continue
        }

        let size = clip.expectedFileSize > 0
          ? clip.expectedFileSize
          : clip.fileSize
        let path = clip.currentPath.isEmpty
          ? URL(fileURLWithPath: project.projectFolderPath)
            .appendingPathComponent(clip.relativePath).path
          : clip.currentPath

        candidates.append(
          PreflightCandidate(
            filename: clip.originalFilename,
            fileSize: size,
            modifiedAt: clip.modifiedAt,
            duration: clip.duration,
            path: path,
            kind: .project,
            locationLabel: project.name
          )
        )

        if clip.currentFilename.caseInsensitiveCompare(clip.originalFilename)
          != .orderedSame {
          candidates.append(
            PreflightCandidate(
              filename: clip.currentFilename,
              fileSize: size,
              modifiedAt: clip.modifiedAt,
              duration: clip.duration,
              path: path,
              kind: .project,
              locationLabel: project.name
            )
          )
        }
      }
    }

    return candidates
  }
}
