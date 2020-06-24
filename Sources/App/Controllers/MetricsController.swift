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

final class MetricsController {

    func index(_ req: Request) throws -> EventLoopFuture<String> {
        let prometheusClient = PrometheusClient()
        MetricsSystem.bootstrap(prometheusClient)
        setTimeDiffMetric(prometheusClient)
        let promise: EventLoopPromise = req.eventLoop.next().makePromise(of: String.self)
        try! MetricsSystem.prometheus().collect(promise.succeed)

        return promise.futureResult
    }

    private func setTimeDiffMetric(_ prom: PrometheusClient) {
        let timeDiff = getTimeDiff()
        let gauge = prom.createGauge(forType: Int.self, named: "TimeDiff")
//        gauge.inc() // Increment by 1
//        gauge.dec(19) // Decrement by given value
        gauge.set(timeDiff)
    }

    private func getTimeDiff(_ d: Double = 1) -> Int {
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
}
