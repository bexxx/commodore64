.importonce 

// Bezier code provided by Digger^Elysium, <3 thanks for opening my mind off from plain sine values :)

.function sampleCurve(t, a, b, c) {
    .return ((a * t + b) * t + c) * t
}

.function solveCurveX(x, ax, bx, cx) {
    .var t0 = 0.0
    .var t1 = 1.0
    .var t2 = x
    .for (var i = 0; i < 8; i++) {
        .var x2 = sampleCurve(t2, ax, bx, cx)
        .if (abs(x2 - x) < 0.001) {
            .return t2
        }
        .var d2 = (3.0 * ax * t2 + 2.0 * bx) * t2 + cx
        .if (abs(d2) < 0.000001) {
            .return t2
        }
        .eval t2 = t2 - (x2 - x) / d2
    }
    .return t2
}

.function cubicBezier(t, x1, y1, x2, y2) {
    .var cx = 3.0 * x1
    .var bx = 3.0 * (x2 - x1) - cx
    .var ax = 1.0 - cx - bx

    .var cy = 3.0 * y1
    .var by = 3.0 * (y2 - y1) - cy
    .var ay = 1.0 - cy - by

    .return sampleCurve(solveCurveX(t, ax, bx, cx), ay, by, cy)
}

// Use https://cubic-bezier.com/ to get x1, y1, x2, y2
.function cubicBezierEasing(time, start, end, duration, x1, y1, x2, y2) {
    .var t = time / duration
    .var y = cubicBezier(t, x1, y1, x2, y2)
    .return start + (end - start) * y
}