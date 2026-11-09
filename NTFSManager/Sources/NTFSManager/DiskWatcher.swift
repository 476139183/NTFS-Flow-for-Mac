import Foundation
import DiskArbitration

/// 用 DiskArbitration 监听插拔和挂载变化
final class DiskWatcher {
    private let session: DASession
    private let onChange: @MainActor () -> Void

    init?(onChange: @escaping @MainActor () -> Void) {
        guard let s = DASessionCreate(kCFAllocatorDefault) else { return nil }
        session = s
        self.onChange = onChange
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let cb: DADiskAppearedCallback = { _, ctx in
            guard let ctx else { return }
            let w = Unmanaged<DiskWatcher>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { w.onChange() }
        }
        let changed: DADiskDescriptionChangedCallback = { _, _, ctx in
            guard let ctx else { return }
            let w = Unmanaged<DiskWatcher>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { w.onChange() }
        }
        DARegisterDiskAppearedCallback(session, nil, cb, ctx)
        DARegisterDiskDisappearedCallback(session, nil, cb, ctx)
        DARegisterDiskDescriptionChangedCallback(session, nil, nil, changed, ctx)
        DASessionScheduleWithRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    deinit {
        DASessionUnscheduleFromRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }
}
