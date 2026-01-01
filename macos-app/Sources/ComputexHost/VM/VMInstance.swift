import Foundation
import Virtualization

enum VMRunMode: Equatable {
    case baseSetup
    case session(SessionKind)
}

final class VMInstance: NSObject, VZVirtualMachineDelegate {
    let id: String
    let virtualMachine: VZVirtualMachine
    let mode: VMRunMode
    private var stateObservation: NSKeyValueObservation?

    init(id: String, virtualMachine: VZVirtualMachine, mode: VMRunMode) {
        self.id = id
        self.virtualMachine = virtualMachine
        self.mode = mode
        super.init()
        self.virtualMachine.delegate = self
        observeState()
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let startBlock = {
                AppLog.info("VM \(self.id): start requested. State=\(self.virtualMachine.state)")
                self.virtualMachine.start { result in
                    switch result {
                    case .success:
                        AppLog.info("VM \(self.id): start completed. State=\(self.virtualMachine.state)")
                        continuation.resume()
                    case .failure(let error):
                        AppLog.error("VM \(self.id): start failed \(error.localizedDescription)")
                        continuation.resume(throwing: VMError.startFailed(error.localizedDescription))
                    }
                }
            }
            self.runOnVMQueue(startBlock)
        }
    }

    func stop() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let stopBlock = {
                AppLog.info("VM \(self.id): stop requested. State=\(self.virtualMachine.state)")
                self.virtualMachine.stop { error in
                    if let error {
                        AppLog.error("VM \(self.id): stop failed \(error.localizedDescription)")
                        continuation.resume(throwing: VMError.stopFailed(error.localizedDescription))
                    } else {
                        AppLog.info("VM \(self.id): stop completed. State=\(self.virtualMachine.state)")
                        continuation.resume()
                    }
                }
            }
            self.runOnVMQueue(stopBlock)
        }
    }

    func pause() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let pauseBlock = {
                AppLog.info("VM \(self.id): pause requested. State=\(self.virtualMachine.state)")
                self.virtualMachine.pause { result in
                    switch result {
                    case .success:
                        AppLog.info("VM \(self.id): pause completed. State=\(self.virtualMachine.state)")
                        continuation.resume()
                    case .failure(let error):
                        AppLog.error("VM \(self.id): pause failed \(error.localizedDescription)")
                        continuation.resume(throwing: VMError.stopFailed(error.localizedDescription))
                    }
                }
            }
            self.runOnVMQueue(pauseBlock)
        }
    }

    func resume() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumeBlock = {
                AppLog.info("VM \(self.id): resume requested. State=\(self.virtualMachine.state)")
                self.virtualMachine.resume { result in
                    switch result {
                    case .success:
                        AppLog.info("VM \(self.id): resume completed. State=\(self.virtualMachine.state)")
                        continuation.resume()
                    case .failure(let error):
                        AppLog.error("VM \(self.id): resume failed \(error.localizedDescription)")
                        continuation.resume(throwing: VMError.startFailed(error.localizedDescription))
                    }
                }
            }
            self.runOnVMQueue(resumeBlock)
        }
    }

    func saveState(to url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let saveBlock = {
                AppLog.info("VM \(self.id): save state to \(url.lastPathComponent).")
                self.virtualMachine.saveMachineStateTo(url: url) { error in
                    if let error {
                        AppLog.error("VM \(self.id): save state failed \(error.localizedDescription)")
                        continuation.resume(throwing: VMError.startFailed(error.localizedDescription))
                    } else {
                        AppLog.info("VM \(self.id): save state completed.")
                        continuation.resume()
                    }
                }
            }
            self.runOnVMQueue(saveBlock)
        }
    }

    func restoreState(from url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let restoreBlock = {
                AppLog.info("VM \(self.id): restore state from \(url.lastPathComponent).")
                self.virtualMachine.restoreMachineStateFrom(url: url) { error in
                    if let error {
                        AppLog.error("VM \(self.id): restore failed \(error.localizedDescription)")
                        continuation.resume(throwing: VMError.startFailed(error.localizedDescription))
                    } else {
                        AppLog.info("VM \(self.id): restore completed. State=\(self.virtualMachine.state)")
                        continuation.resume()
                    }
                }
            }
            self.runOnVMQueue(restoreBlock)
        }
    }

    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        // TODO: surface to host UI
        NSLog("VM stopped with error: %@", error.localizedDescription)
    }

    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        // TODO: surface to host UI
        AppLog.info("VM \(id): guest stopped")
    }

    private func runOnVMQueue(_ block: @escaping () -> Void) {
        if #available(macOS 26.0, *) {
            virtualMachine.queue.async(execute: block)
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    private func observeState() {
        stateObservation = virtualMachine.observe(\.state, options: [.initial, .new]) { [id] _, change in
            let state = change.newValue ?? .stopped
            AppLog.info("VM \(id): state -> \(state)")
        }
    }
}
