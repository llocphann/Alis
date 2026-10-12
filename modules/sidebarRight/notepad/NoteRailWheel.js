// Pure note-rail wheel routing. Qt's pixelDelta (touchpads) and angleDelta
// (discrete wheels) are different units; never treat every touchpad packet
// as a full note switch. One event can advance at most one note.
function idle() {
    return {direction: 0, distance: 0, lastAt: 0, lastStepAt: -1};
}

function advance(previous, input, now) {
    var phase = Number(input.phase || 0);
    var state = Object.assign({}, previous || idle());
    if (phase === 3)
        return {state: idle(), step: 0, accepted: false};
    // Kinetic tail must never skip more notes after fingers leave the pad.
    if (phase === 4)
        return {state: idle(), step: 0, accepted: true};
    if (input.blocked)
        return {state: idle(), step: 0, accepted: false};

    var pixel = input.pixelDelta || {};
    var angle = input.angleDelta || {};
    var py = Number(pixel.y) || 0, ay = Number(angle.y) || 0;
    // Some compositors convert Shift+vertical wheel into a horizontal axis.
    // The note rail interprets it as vertical selection, not horizontal pan.
    if (!py && !ay && input.shifted) {
        py = Number(pixel.x) || 0;
        ay = Number(angle.x) || 0;
    }
    var amount = py ? py / 48 : ay / 120;
    if (!Number.isFinite(amount) || !amount)
        return {state: state, step: 0, accepted: false};

    if (phase === 1 || (state.lastAt && now - state.lastAt > 240))
        state = idle();
    var direction = amount < 0 ? 1 : -1;
    if (state.direction !== direction) {
        state.direction = direction;
        state.distance = 0;
        state.lastStepAt = -1;
    }
    state.lastAt = now;
    state.distance = Math.min(1.99, state.distance + Math.abs(amount));
    if (state.distance >= 1
            && (state.lastStepAt < 0 || now - state.lastStepAt >= 140)) {
        state.distance = Math.max(0, state.distance - 1);
        state.lastStepAt = now;
        return {state: state, step: direction, accepted: true};
    }
    return {state: state, step: 0, accepted: true};
}
