import Foundation
import Darwin

private func handleException(_ exception: NSException) {
    AppLog.error("Uncaught exception: \(exception.name.rawValue) - \(exception.reason ?? "unknown")")
    AppLog.error(exception.callStackSymbols.joined(separator: "\n"))
}

private var didHandleSignal = false

private func handleSignal(_ signalNumber: Int32) {
    if didHandleSignal {
        return
    }
    didHandleSignal = true
    AppLog.error("Received signal: \(signalNumber)")
    Darwin.signal(signalNumber, SIG_DFL)
    raise(signalNumber)
}

enum CrashLogging {
    static func install() {
        NSSetUncaughtExceptionHandler(handleException)
        signal(SIGTRAP, handleSignal)
        signal(SIGABRT, handleSignal)
        signal(SIGILL, handleSignal)
        signal(SIGSEGV, handleSignal)
        signal(SIGBUS, handleSignal)
    }
}
