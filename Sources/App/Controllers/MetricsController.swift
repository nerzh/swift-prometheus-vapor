//
//  MetricsController.swift
//  
//
//  Created by Oleh Hudeichuk on 24.06.2020.
//

import Vapor
import Prometheus
import Metrics
import SwiftExtensionsPack
import FileUtils
import SwiftLinuxStat

final class MetricsController {

    let indexGroup: DispatchGroup = .init()

    func index(_ req: Request) throws -> EventLoopFuture<String> {
        let prometheusClient: PrometheusClient = try! MetricsSystem.prometheus()
        setTimeDiffMetric(prometheusClient)

        getDiskLoad { (metric) in
            self.setDiskMetric(metric)
        }
        getNetLoad { (metric) in
            self.setNetMetric(metric)
        }
        getCPU { (metric) in
            self.setCPUMetric(metric)
        }
        setMemMetric(getMemLoad())
        setDiskSpaceMetric(getDiskSpace())

        indexGroup.wait()

        let promise: EventLoopPromise = req.eventLoop.next().makePromise(of: String.self)
        prometheusClient.collect(promise.succeed)

        return promise.futureResult
    }

    
    private func setTimeDiffMetric(_ prom: PrometheusClient) {
        let timeDiff = getTimeDiff()
        let gauge = prom.createGauge(forType: Int.self, named: "TimeDiff")
//        gauge.inc() // Increment by 1
//        gauge.dec(19) // Decrement by given value
        gauge.set(timeDiff)
    }

    private func setDiskMetric(_ metric: DiskLoad) {
        let label: String = "diskload"
        Gauge(label: label, dimensions: [("type", "read")]).record(metric.load.read)
        Gauge(label: label, dimensions: [("type", "write")]).record(metric.load.write)
        Gauge(label: label, dimensions: [("type", "busy")]).record(metric.busy)
        Gauge(label: label, dimensions: [("type", "IOsRead")]).record(metric.iops.readIOs)
        Gauge(label: label, dimensions: [("type", "IOsWrite")]).record(metric.iops.writeIOs)
    }

    private func setDiskSpaceMetric(_ metric: SwiftLinuxStat.DiskSpace) {
        let label: String = "diskSpace"
        Gauge(label: label, dimensions: [("type", "size"), ("name", metric.name)]).record(metric.size)
        Gauge(label: label, dimensions: [("type", "avail"), ("name", metric.name)]).record(metric.avail)
        Gauge(label: label, dimensions: [("type", "used"), ("name", metric.name)]).record(metric.used)
        Gauge(label: label, dimensions: [("type", "use"), ("name", metric.name)]).record(metric.use)
    }

    private func setNetMetric(_ metric: SwiftLinuxStat.NetLoad) {
        let label: String = "netload"
        Gauge(label: label, dimensions: [("type", "receive")]).record(metric.receive)
        Gauge(label: label, dimensions: [("type", "transmit")]).record(metric.transmit)
    }

    private func setCPUMetric(_ metric: SwiftLinuxStat.Percent) {
        let label: String = "cpuload"
        Gauge(label: label).record(metric)
    }

    private func setMemMetric(_ metric: SwiftLinuxStat.MemLoad) {
        let label: String = "memload"
        Gauge(label: label, dimensions: [("type", "memTotal")]).record(metric.memTotal)
        Gauge(label: label, dimensions: [("type", "memFree")]).record(metric.memFree)
        Gauge(label: label, dimensions: [("type", "memAvail")]).record(metric.memAvailable)
        Gauge(label: label, dimensions: [("type", "memBuffers")]).record(metric.buffers)
        Gauge(label: label, dimensions: [("type", "swapTotal")]).record(metric.swapTotal)
        Gauge(label: label, dimensions: [("type", "swapFree")]).record(metric.swapFree)
    }


    // MARK: Collector Helpers
    private func getTimeDiff() -> Int {
        guard let scriptDir = Environment.get("ScriptDir") else { return 0 }
        let command = "cd \(scriptDir)/ && ./check_node_sync_status.sh"
        if let out = try? systemCommand(command),
            let maybeTimeDiff = out.regexp(#"TIME_DIFF.+(-*\d+)"#)[1],
            let timeDiff = Int(maybeTimeDiff)
        {
            return timeDiff
        }

        return 0
    }

    private func getDiskSpace() -> Int {
        guard let scriptDir = Environment.get("ScriptDir") else { return 0 }
        let command = "cd \(scriptDir)/ && ./check_node_sync_status.sh"
        if let out = try? systemCommand(command),
            let maybeTimeDiff = out.regexp(#"TIME_DIFF.+(-*\d+)"#)[1],
            let timeDiff = Int(maybeTimeDiff)
        {
            return timeDiff
        }

        return 0
    }

    typealias DiskLoad = (load: SwiftLinuxStat.DiskLoad, iops: SwiftLinuxStat.DiskIOs, busy: SwiftLinuxStat.Percent)
    private func getDiskLoad(_ handler: @escaping (DiskLoad) -> Void) {
        let disk: SwiftLinuxStat.Disk = .init()
        indexGroup.enter()
        Thread {
            disk.update()
            let kb: Float = 1024
            let mb: Float = kb * 1024
            var diskLoad: SwiftLinuxStat.DiskLoad = disk.diskLoadPerSecond(current: false)
            diskLoad.read = (diskLoad.read / mb).round(toDecimalPlaces: 2)
            diskLoad.write = (diskLoad.write / mb).round(toDecimalPlaces: 2)

            let diskBusy: SwiftLinuxStat.Percent = disk.diskBusy(current: false)
            let diskIOs: SwiftLinuxStat.DiskIOs = disk.diskIOs(current: false)

            handler((load: diskLoad, iops: diskIOs, busy: diskBusy))
            self.indexGroup.leave()
        }.start()
    }

    private func getDiskSpace() -> SwiftLinuxStat.DiskSpace {
        let disk: SwiftLinuxStat.Disk = .init()
        let mb: Float = 1024
        var diskSpace: SwiftLinuxStat.DiskSpace = disk.diskSpace()
        diskSpace.size = (diskSpace.size / mb).round(toDecimalPlaces: 2)
        diskSpace.avail = (diskSpace.avail / mb).round(toDecimalPlaces: 2)
        diskSpace.used = (diskSpace.used / mb).round(toDecimalPlaces: 2)

        return diskSpace
    }

    private func getNetLoad(_ handler: @escaping (SwiftLinuxStat.NetLoad) -> Void) {
        let net: SwiftLinuxStat.Net = .init()
        indexGroup.enter()
        Thread {
            net.update()
            let kb: Float = 1024
            let mb: Float = kb * 1024
            var netLoad: SwiftLinuxStat.NetLoad = net.netLoadPerSecond(current: false)
            netLoad.receive = (netLoad.receive / mb).round(toDecimalPlaces: 2)
            netLoad.transmit = (netLoad.transmit / mb).round(toDecimalPlaces: 2)
            handler(netLoad)
            self.indexGroup.leave()
        }.start()
    }

    private func getCPU(_ handler: @escaping (SwiftLinuxStat.Percent) -> Void) {
        let cpu: SwiftLinuxStat.CPU = .init()
        indexGroup.enter()
        Thread {
            cpu.update()
            let cpuLoad: SwiftLinuxStat.Percent = cpu.cpuLoad(current: false)
            handler(cpuLoad)
            self.indexGroup.leave()
        }.start()
    }

    private func getMemLoad() -> SwiftLinuxStat.MemLoad {
        let mem: SwiftLinuxStat.Mem = .init()
        let mb: Float = 1024
        var memLoad: SwiftLinuxStat.MemLoad = mem.memLoad()
        memLoad.memTotal = (memLoad.memTotal / mb).round(toDecimalPlaces: 2)
        memLoad.memFree = (memLoad.memFree / mb).round(toDecimalPlaces: 2)
        memLoad.memAvailable = (memLoad.memAvailable / mb).round(toDecimalPlaces: 2)
        memLoad.buffers = (memLoad.buffers / mb).round(toDecimalPlaces: 2)
        memLoad.swapTotal = (memLoad.swapTotal / mb).round(toDecimalPlaces: 2)
        memLoad.swapFree = (memLoad.swapFree / mb).round(toDecimalPlaces: 2)

        return memLoad
    }
}
