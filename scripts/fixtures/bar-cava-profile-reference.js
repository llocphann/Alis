// Frozen pre-cache shaping algorithm; numeric CAVA frames, exact arithmetic.
.pragma library
function processedSource(root) {
        const source = root.points ?? []
        const count = source.length ?? 0
        if (!root.active || count === 0)
            return []

        const selected = root._selectedScratch
        selected.length = count
        const strength = Math.max(0, Math.min(1, root.accentStrength))
        const applyProfile = strength > 0 && root.frequencyProfile !== "flat"

        for (let i = 0; i < count; ++i) {
            let value = Number(source[i]) || 0
            if (applyProfile) {
                const domain = count > 1 ? i / (count - 1) : 0.5
                const frequency = root.mirroredStereo
                    ? Math.abs(domain * 2 - 1) : domain
                const weight = root._profileWeight(frequency)
                value *= 1 + (weight - 1) * strength
            }
            selected[i] = value
        }

        const radius = Math.max(0, Math.round(root.smoothing))
        if (radius === 0 || count < 3)
            return selected

        const smoothed = root._smoothScratch
        smoothed.length = count
        let start = 0
        let end = Math.min(count - 1, radius)
        let sum = 0
        for (let i = start; i <= end; ++i)
            sum += selected[i]

        for (let i = 0; i < count; ++i) {
            const nextStart = Math.max(0, i - radius)
            const nextEnd = Math.min(count - 1, i + radius)
            while (start < nextStart)
                sum -= selected[start++]
            while (end < nextEnd)
                sum += selected[++end]
            smoothed[i] = sum / Math.max(1, end - start + 1)
        }
        return smoothed
    }

