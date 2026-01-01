import SwiftUI
import Virtualization

struct VMDisplayView: NSViewRepresentable {
    var virtualMachine: VZVirtualMachine

    func makeNSView(context: Context) -> VZVirtualMachineView {
        let view = VZVirtualMachineView()
        view.capturesSystemKeys = true
        if #available(macOS 14.0, *) {
            view.automaticallyReconfiguresDisplay = true
        }
        view.virtualMachine = virtualMachine
        return view
    }

    func updateNSView(_ view: VZVirtualMachineView, context: Context) {
        if #available(macOS 14.0, *) {
            view.automaticallyReconfiguresDisplay = true
        }
        view.virtualMachine = virtualMachine
    }
}
