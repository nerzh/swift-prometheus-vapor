import App
import Vapor

var env = try Environment.detect()
try LoggingSystem.bootstrap(from: &env)
//let numberCores: Int = Int(Environment.get("NumberCores") ?? "") ?? System.coreCount
let numberCores: Int = 2
let app = Application(env, .shared(MultiThreadedEventLoopGroup(numberOfThreads: numberCores)))
defer { app.shutdown() }
try configure(app)
try app.run()
