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
        let diskLoadRead: Gauge = Gauge(label: label, dimensions: [("type", "read")])
        let diskLoadWrite: Gauge = Gauge(label: label, dimensions: [("type", "write")])
        let diskLoadBusy: Gauge = Gauge(label: label, dimensions: [("type", "busy")])
        let diskLoadIOsRead: Gauge = Gauge(label: label, dimensions: [("type", "IOsRead")])
        let diskLoadIOsWrite: Gauge = Gauge(label: label, dimensions: [("type", "IOsWrite")])
        diskLoadRead.record(metric.load.read)
        diskLoadWrite.record(metric.load.write)
        diskLoadBusy.record(metric.busy)
        diskLoadIOsRead.record(metric.iops.readIOs)
        diskLoadIOsWrite.record(metric.iops.writeIOs)
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
            let cpuLoad: SwiftLinuxStat.Percent = cpu.cpuLoad()
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
