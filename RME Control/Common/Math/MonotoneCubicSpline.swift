import Foundation

/// Монотонный кубический сплайн (Fritsch–Carlson): гладкая интерполяция по таблице точек
/// без «перелётов», поэтому обратная функция dB → положение фейдера остаётся монотонной.
struct MonotoneCubicSpline {
    let xs: [Double]
    let ys: [Double]
    let ms: [Double]

    init(points: [(Double, Double)]) {
        let pts = points.sorted { $0.0 < $1.0 }
        xs = pts.map { $0.0 }
        ys = pts.map { $0.1 }
        let n = xs.count
        var m = [Double](repeating: 0, count: n)
        if n > 1 {
            var d = [Double](repeating: 0, count: n - 1)
            for i in 0..<(n - 1) {
                d[i] = (ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i])
            }
            m[0] = d[0]
            m[n - 1] = d[n - 2]
            for i in 1..<(n - 1) {
                if d[i - 1] * d[i] <= 0 {
                    m[i] = 0
                } else {
                    m[i] = 2 / (1 / d[i - 1] + 1 / d[i])
                }
            }
        }
        ms = m
    }

    func interpolate(_ x: Double) -> Double {
        if x <= xs[0] { return ys[0] }
        if x >= xs[xs.count - 1] { return ys[ys.count - 1] }
        var lo = 0
        var hi = xs.count - 1
        while lo + 1 < hi {
            let mid = (lo + hi) / 2
            if xs[mid] <= x { lo = mid } else { hi = mid }
        }
        let h = xs[hi] - xs[lo]
        if h == 0 { return ys[lo] }
        let t = (x - xs[lo]) / h
        let t2 = t * t
        let t3 = t2 * t
        let h00 = 2 * t3 - 3 * t2 + 1
        let h10 = t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2
        let h11 = t3 - t2
        return h00 * ys[lo] + h10 * h * ms[lo] + h01 * ys[hi] + h11 * h * ms[hi]
    }
}
