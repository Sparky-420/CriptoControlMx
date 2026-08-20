package mx.criptocontrolmx.app

import kotlin.math.max

internal object WalletImageDecodePlanner {
    fun inSampleSize(width: Int, height: Int, maxLongEdge: Int): Int {
        require(width > 0 && height > 0) { "Image bounds must be positive" }
        require(maxLongEdge > 0) { "maxLongEdge must be positive" }
        var sample = 1
        val maxSampledLongEdge = maxLongEdge * 2
        while (max(width, height) / sample > maxSampledLongEdge) {
            sample *= 2
        }
        return sample
    }
}
