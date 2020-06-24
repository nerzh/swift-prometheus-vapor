import Vapor

func routes(_ app: Application) throws {
//    app.get("metrics") { req -> String in
//        return "Hello, world!"
//    }

    let metricsCtrl = MetricsController()
    app.get("metrics", use: metricsCtrl.index)
}
