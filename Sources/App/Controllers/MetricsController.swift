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
        let metric: DiskLoad = getDiskLoad()
        indexGroup.wait()
        setTimeDiffMetric(prometheusClient)
        setDiskMetric(metric)
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
        let diskLoadName: String = "diskLoad"
        let diskLoadRead: Gauge = Gauge(label: diskLoadName, dimensions: [("type", "read")])
        let diskLoadWrite: Gauge = Gauge(label: diskLoadName, dimensions: [("type", "write")])
        let diskLoadBusy: Gauge = Gauge(label: diskLoadName, dimensions: [("type", "busy")])
        let diskLoadIOsRead: Gauge = Gauge(label: diskLoadName, dimensions: [("type", "IOsRead")])
        let diskLoadIOsWrite: Gauge = Gauge(label: diskLoadName, dimensions: [("type", "IOsWrite")])
        diskLoadRead.record(metric.load.read)
        diskLoadWrite.record(metric.load.write)
        diskLoadBusy.record(metric.busy)
        diskLoadIOsRead.record(metric.iops.readIOs)
        diskLoadIOsWrite.record(metric.iops.writeIOs)
    }

    private func setNetMetric(_ prom: PrometheusClient) {
        let timeDiff = getTimeDiff()
        let gauge = prom.createGauge(forType: Int.self, named: "TimeDiff")
        //        gauge.inc() // Increment by 1
        //        gauge.dec(19) // Decrement by given value
        gauge.set(timeDiff)
    }

    private func setCPUMetric(_ prom: PrometheusClient) {
        let timeDiff = getTimeDiff()
        let gauge = prom.createGauge(forType: Int.self, named: "TimeDiff")
        //        gauge.inc() // Increment by 1
        //        gauge.dec(19) // Decrement by given value
        gauge.set(timeDiff)
    }

    private func setMemMetric(_ prom: PrometheusClient) {
        let timeDiff = getTimeDiff()
        let gauge = prom.createGauge(forType: Int.self, named: "TimeDiff")
        //        gauge.inc() // Increment by 1
        //        gauge.dec(19) // Decrement by given value
        gauge.set(timeDiff)
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
    private func getDiskLoad() -> DiskLoad {
        let disk: SwiftLinuxStat.Disk = .init()
        indexGroup.enter()
        Thread {
            disk.update()
            self.indexGroup.leave()
        }.start()
        let kb: Float = 1024
        let mb: Float = kb * 1024
        var diskLoad: SwiftLinuxStat.DiskLoad = disk.diskLoadPerSecond(current: false)
        diskLoad.read = (diskLoad.read / mb).round(toDecimalPlaces: 3)
        diskLoad.write = (diskLoad.write / mb).round(toDecimalPlaces: 3)

        let diskBusy: SwiftLinuxStat.Percent = disk.diskBusy(current: false)
        let diskIOs: SwiftLinuxStat.DiskIOs = disk.diskIOs(current: false)

        return (load: diskLoad, iops: diskIOs, busy: diskBusy)
    }

    private func getNetLoad() -> SwiftLinuxStat.NetLoad {
        let net: SwiftLinuxStat.Net = .init()
        indexGroup.enter()
        Thread {
            net.update()
            self.indexGroup.leave()
        }.start()
        let kb: Float = 1024
        let mb: Float = kb * 1024
        var netLoad: SwiftLinuxStat.NetLoad = net.netLoadPerSecond(current: false)
        netLoad.receive = (netLoad.receive / mb).round(toDecimalPlaces: 3)
        netLoad.transmit = (netLoad.transmit / mb).round(toDecimalPlaces: 3)

        return netLoad
    }

    private func getCPU() -> SwiftLinuxStat.Percent {
        let cpu: SwiftLinuxStat.CPU = .init()
        indexGroup.enter()
        Thread {
            cpu.update()
            self.indexGroup.leave()
        }.start()
        let cpuLoad: SwiftLinuxStat.Percent = cpu.cpuLoad()

        return cpuLoad
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
