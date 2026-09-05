import Foundation
import Observation
import Sparkle

@MainActor @Observable
final class UpdateService: NSObject, SPUUpdaterDelegate {
    private(set) var isConfigured = false
    private(set) var configurationMessage = "Updates are unavailable in this local build because no HTTPS feed and Sparkle public key were configured."
    private var controller: SPUStandardUpdaterController?
    private var deferredInstall: (() -> Void)?
    private var deferredWaiter: Task<Void, Never>?
    private let enabled: Bool
    var shouldDeferInstall: () -> Bool = { false }
    var prepareForInstall: () -> Void = {}

    init(enabled: Bool = true) {
        self.enabled = enabled
        super.init()
    }

    func start() {
        guard enabled, controller == nil else { return }
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feed), url.scheme == "https", url.host?.isEmpty == false,
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else { return }
        isConfigured = true
        configurationMessage = "Updates are securely delivered by Sparkle."
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        controller.startUpdater()
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }
    var automaticallyDownloads: Bool {
        get { controller?.updater.automaticallyDownloadsUpdates ?? false }
        set { controller?.updater.automaticallyDownloadsUpdates = newValue }
    }
    func checkNow() { controller?.checkForUpdates(nil) }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        let shouldPostpone = postponeIfBusy(installHandler)
        if !shouldPostpone { prepareForInstall() }
        return shouldPostpone
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        postponeIfBusy(immediateInstallHandler)
    }

    private func postponeIfBusy(_ installHandler: @escaping () -> Void) -> Bool {
        guard shouldDeferInstall() else { return false }
        deferredInstall = installHandler
        configurationMessage = "Update ready. Installation is deferred until the active timer and reminder finish."
        deferredWaiter?.cancel()
        deferredWaiter = Task { [weak self] in
            while let self, self.shouldDeferInstall(), !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled, let self, let handler = self.deferredInstall else { return }
            self.prepareForInstall()
            self.deferredInstall = nil
            self.deferredWaiter = nil
            handler()
        }
        return true
    }
}
