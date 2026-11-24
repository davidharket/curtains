import Foundation

struct PetMotion {
    var x: CGFloat
    var y: CGFloat
    private var goal: CGFloat
    private var goalY: CGFloat
    private var cruise = CGFloat.random(in: 26...88)
    private var rest: Double
    private var velocity: CGFloat = 0
    private(set) var stride: CGFloat = 0
    private(set) var facesLeft = false

    init(position: CGFloat) {
        x = position
        y = .random(in: 2...17)
        goalY = y
        goal = position
        rest = .random(in: 0...1.1)
    }

    mutating func advance(seconds dt: Double, width: CGFloat, side: CGFloat) {
        let margin = min(width / 2, side / 2 + 3)
        let range = margin...max(margin, width - margin)
        x = min(max(x, range.lowerBound), range.upperBound)
        goal = min(max(goal, range.lowerBound), range.upperBound)
        if rest > 0 { rest -= dt; return }
        let delta = goal - x
        if abs(delta) < 0.6 {
            velocity = 0
            rest = .random(in: 0.4...2.8)
            let reach = max(side * 2, width * 0.30)
            let low = max(range.lowerBound, x - reach)
            let high = min(range.upperBound, x + reach)
            goal = .random(in: low...high)
            goalY = .random(in: 2...17)
            cruise = .random(in: 26...88)
            return
        }
        facesLeft = delta < 0
        let desired = min(cruise, sqrt(2 * 110 * abs(delta)))
        velocity = min(desired, velocity + 110 * dt)
        let step = min(abs(delta), velocity * dt)
        y += (goalY - y) * step / abs(delta)
        x += facesLeft ? -step : step
        stride += step / 5
    }
}
