
.function easeInOutCubic(time, start, end, duration) {
    .var change = end - start
    .var t = time / (duration / 2)
    
    .if (t < 1) {
        .return change / 2 * t * t * t + start
    } else {
        .eval t -= 2
        .return change / 2 * (t * t * t + 2) + start
    }
}

.function easeInOutBack(time, start, end, duration) {
    .var overshoot = 1.70158
    .var change = end - start
    .var t = time / (duration / 2)
    .if (t < 1) {
        .eval overshoot *= 1.525
        .return change / 2 * (t * t * ((overshoot + 1) * t - overshoot)) + start
    } else {
        .eval t -= 2
        .eval overshoot *= 1.525
        .return change / 2 * (t * t * ((overshoot + 1) * t + overshoot) + 2) + start
    }
}

.function easeOutBounce(time, start, end, duration) {
    .var change = end - start
    .var t = time / duration
    .if (t < 1 / 2.75) {
        .return change * (7.5625 * t * t) + start
    } else .if (t < 2 / 2.75) {
        .eval t -= 1.5 / 2.75
        .return change * (7.5625 * t * t + 0.75) + start
    } else .if (t < 2.5 / 2.75) {
        .eval t -= 2.25 / 2.75
        .return change * (7.5625 * t * t + 0.9375) + start
    } else {
        .eval t -= 2.625 / 2.75
        .return change * (7.5625 * t * t + 0.984375) + start
    }
}

.function easeOutElastic(time, start, end, duration) {
    .var change = end - start
    .var t = time / duration
    .var p = duration * 0.3
    .var s = p / 4
    .if (t == 1) {
        .return start + change
    }
    .return change * pow(2, -10 * t) * sin((t * duration - s) * (2 * PI) / p) + change + start
}

.function easeInBack (t, b, e, d) {
    .const c = e - b
    .const s = 1.70158;
    .return c*(t/=d)*t*((s+1)*t - s) + b;
}

.function easeOutBack (t, b, e, d) {
    .var c = e - b
    .const s = 1.70158;
    .return c*((t=t/d-1)*t*((s+1)*t + s) + 1) + b;
}

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
            // .break
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

// Example
// .var startValue = 0
// .var endValue = 100
// .var durationValue = 10
// .var x1 = 0.25  // First control point X
// .var y1 = 0.1   // First control point Y
// .var x2 = 0.25  // Second control point X
// .var y2 = 1.0   // Second control point Y

// .print "Cubic Bezier easing values:"
// .for (var i = 0; i <= durationValue; i++) {
//     .var result = cubicBezierEasing(i, startValue, endValue, durationValue, x1, y1, x2, y2)
//     .print "Time " + i + ": " + result
// }

.function easingSine(time, start, end, duration) {
    .var progress = time / duration
    .var eased = -sin(progress * 2 * PI) * 0.5 + 0.5
    .return start + (end - start) * eased
}

.function easingCosine(time, start, end, duration) {
    .var progress = time / duration
    .var eased = -cos(progress * 2 * PI) * 0.5 + 0.5
    .return start + (end - start) * eased
}