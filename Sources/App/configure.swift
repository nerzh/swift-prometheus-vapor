import Vapor
import Metrics
import Prometheus

// configures your application
public func configure(_ app: Application) throws {
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
//    app.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 2)
    // register routes
    

    app.http.server.configuration.port = Int(Environment.get("Port") ?? "8080") ?? 8080
    app.http.server.configuration.hostname = Environment.get("Host") ?? "127.0.0.1"

    let prometheusClient = PrometheusClient()
    MetricsSystem.bootstrap(prometheusClient)

    try routes(app)
}
