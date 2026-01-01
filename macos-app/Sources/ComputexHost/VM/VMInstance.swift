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

    init(id: String, virtualMachine: VZVirtualMachine, mode: VMRunMode) {
        self.id = id
        self.virtualMachine = virtualMachine
        self.mode = mode
        super.init()
        self.virtualMachine.delegate = self
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { continuation in
            virtualMachine.start { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: VMError.startFailed(error.localizedDescription))
                }
            }
        }
    }

    func stop() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            virtualMachine.stop { error in
                if let error {
                    continuation.resume(throwing: VMError.stopFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        // TODO: surface to host UI
        NSLog("VM stopped with error: %@", error.localizedDescription)
    }

    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        // TODO: surface to host UI
        NSLog("VM stopped")
    }
}
