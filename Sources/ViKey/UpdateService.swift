import AppKit
import CryptoKit
import Foundation

final class UpdateService {
    static let shared = UpdateService()

    private let latestReleaseURL = URL(string: "https://api.github.com/repos/phuongtai/ViKey/releases/latest")!
    private let releasesPageURL = URL(string: "https://github.com/phuongtai/ViKey/releases/latest")!

    private init() {}

    func checkForUpdates(presentWhenCurrent: Bool) {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ViKey", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            DispatchQueue.main.async {
                guard let data,
                      let response = response as? HTTPURLResponse,
                      response.statusCode == 200,
                      let release = try? JSONDecoder().decode(Release.self, from: data) else {
                    if presentWhenCurrent { self.showError(error) }
                    return
                }
                self.handle(release: release, presentWhenCurrent: presentWhenCurrent)
            }
        }.resume()
    }

    private func handle(release: Release, presentWhenCurrent: Bool) {
        guard let remoteVersion = Version(release.tagName), let localVersion = Version.current else {
            if presentWhenCurrent { showError(nil) }
            return
        }
        guard remoteVersion > localVersion else {
            if presentWhenCurrent { showCurrentVersion(localVersion) }
            return
        }

        let alert = NSAlert()
        alert.messageText = "Có bản ViKey mới: \(remoteVersion)"
        alert.informativeText = "Nhấn Cập nhật để tự tải, cài đặt và mở lại ViKey."
        alert.addButton(withTitle: "Cập nhật")
        alert.addButton(withTitle: "Để sau")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        install(release: release, version: remoteVersion)
    }

    private func install(release: Release, version: Version) {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            showError(nil)
            return
        }
        guard let asset = release.assets.first(where: { $0.name == "ViKey-\(version).zip" }),
              let downloadURL = URL(string: asset.browserDownloadURL) else {
            showError(nil)
            return
        }

        URLSession.shared.downloadTask(with: downloadURL) { [weak self] archiveURL, _, error in
            guard let self else { return }
            DispatchQueue.main.async {
                guard let archiveURL else {
                    self.showError(error)
                    return
                }
                self.verifyAndInstall(archiveURL: archiveURL, asset: asset)
            }
        }.resume()
    }

    private func verifyAndInstall(archiveURL: URL, asset: ReleaseAsset) {
        defer { try? FileManager.default.removeItem(at: archiveURL) }
        guard let expectedDigest = asset.digest?.split(separator: ":", maxSplits: 1).last,
              let archive = try? Data(contentsOf: archiveURL) else {
            showError(nil)
            return
        }
        let digest = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        guard digest == expectedDigest else {
            showError(nil)
            return
        }

        let stagingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViKey-update-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unzip.arguments = ["-x", "-k", archiveURL.path, stagingDirectory.path]
            try unzip.run()
            unzip.waitUntilExit()

            let replacement = stagingDirectory.appendingPathComponent("ViKey.app")
            guard unzip.terminationStatus == 0,
                  FileManager.default.fileExists(atPath: replacement.path),
                  Bundle(url: replacement)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
                try? FileManager.default.removeItem(at: stagingDirectory)
                showError(nil)
                return
            }
            replaceApp(with: replacement, stagingDirectory: stagingDirectory)
        } catch {
            try? FileManager.default.removeItem(at: stagingDirectory)
            showError(error)
        }
    }

    private func replaceApp(with replacement: URL, stagingDirectory: URL) {
        let scriptURL = stagingDirectory.appendingPathComponent("install-update.sh")
        let script = """
        #!/bin/sh
        while kill -0 "$1" 2>/dev/null; do sleep 1; done
        rm -rf "$3"
        /usr/bin/ditto "$2" "$3"
        open -n "$3"
        rm -rf "$4"
        """
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            let installer = Process()
            installer.executableURL = URL(fileURLWithPath: "/bin/sh")
            installer.arguments = [scriptURL.path, "\(ProcessInfo.processInfo.processIdentifier)", replacement.path,
                                   Bundle.main.bundleURL.path, stagingDirectory.path]
            try installer.run()
            NSApp.terminate(nil)
        } catch {
            showError(error)
        }
    }

    private func showCurrentVersion(_ version: Version) {
        let alert = NSAlert()
        alert.messageText = "ViKey đã là bản mới nhất"
        alert.informativeText = "Bạn đang dùng phiên bản \(version)."
        alert.runModal()
    }

    private func showError(_ error: Error?) {
        let alert = NSAlert()
        alert.messageText = "Không thể cập nhật ViKey"
        alert.informativeText = error?.localizedDescription ?? "Hãy thử lại sau."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Mở Releases")
        alert.addButton(withTitle: "Đóng")
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(releasesPageURL) }
    }
}

private struct Release: Decodable {
    let tagName: String
    let assets: [ReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

private struct ReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: String
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case digest
    }
}

private struct Version: Comparable, CustomStringConvertible {
    let components: [Int]

    init?(_ value: String) {
        let value = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let pieces = value.split(separator: ".")
        guard !pieces.isEmpty, pieces.allSatisfy({ Int($0) != nil }) else { return nil }
        components = pieces.map { Int($0)! }
    }

    static var current: Version? {
        Version(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
    }

    static func < (lhs: Version, rhs: Version) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    var description: String { components.map(String.init).joined(separator: ".") }
}