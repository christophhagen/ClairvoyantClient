# ClairvoyantClient

A client to access [Clairvoyant](https://github.com/christophhagen/Clairvoyant) metrics exposed on a [Vapor server](https://github.com/christophhagen/ClairvoyantVapor).

## Usage

Accessing metrics on a server is managed through a `MetricConsumer`, which is intended to work with all metrics from a single server.

```swift
let consumer = MetricConsumer(url: myServerURL, accessProvider: ...)
```

It's possible to list all metrics available on the server.

```swift
let list: [MetricInfo] = try await consumer.list()
```

Individual metrics can then be accessed by creating `ComsumableMetric`s.

```swift
let description = list.first!
let myMetric = await consumer.metric(from: description, as: Int.self)
```

Then, access values of the metric:

```swift
let last = try await myMetric.lastValue() // Timestamped<Int>?
let range = Date.now.addintTimeInterval(-100)...Date.now // last 100 seconds
let history = try await myMetric.history(in: range)
```

### Generic access

Sometimes you may want to just print textual representations of a list of metrics, without wanting to handle each specific type separately.
It's possible to use consumable metrics in a generic way through the `GenericConsumableMetric` protocol.

```swift
let genericMetric = try await consumer.genericMetric(from: description)
let description = try await genericMetric.lastValueDescription() // Timestamped<String>?
```

Note that custom types need special treatment, as detailed [below](#custom-types).

### Access control

Server metrics should be protected by access control, and the clients must provide the appropriate authentication.
Adopt the `RequestAccessProvider` protocol to match a custom implementation of access control on the server, or simply use a `String` token when using built-in types on the server side (like `String` or `ScopedAccessToken`).

```swift
let consumer = MetricConsumer(url: ..., accessProvider: "MySecret")
```

### Custom types

Assuming that a server provides a value of a custom type, then the client needs to implement a compatible type to access the values.
The type on the server and client side must both use the same `MetricType`, and be compatible in terms of encoding and decoding.
It's best to simply use the same type definition on both sides.

Assuming we have a metric of type `Player` on the server:

```swift
struct Player: MetricValue, CustomStringConvertible {

    static let valueType: MetricType = .custom(named: "Player")
    
    let name: String
    
    let score: Int
    
    var description: String { "\(name) (\(score))"}
}
```

Then on the client side, we can just do:

```swift
let myMetric: ConsumableMetric<Player> = metricConsumer.metric(id: "player.current")
```

One special addition should be made when using `GenericConsumableMetric`s to use metrics in type-erased ways, e.g. in SwiftUI views.
It's not possible for a `MetricConsumer` to decode custom types without knowing about the type, so each custom type used in generic metrics should be registered with the consumer:

```swift
metricConsumer.register(customType: Player.self, named: "Player")
```

Now, textual descriptions of the generic metric gives useful output:

```swift
let genericMetric = myMetric as GenericConsumableMetric
let description = try await genericMetric.lastValueDescription()!.value
print(description) // Prints "Alice (42)"
```
