package io.github.pepicrft.faro

/** Bootstrap bridge: Rust owns UTF-8 metadata; no Java heap objects cross JNI. */
class FaroCore {
    private external fun fieldLength(id: Int): Int

    private external fun fieldByte(id: Int, offset: Int): Int

    val name: String get() = field(0)
    val tagline: String get() = field(1)
    val status: String get() = field(2)
    val version: String get() = field(3)

    private fun field(id: Int): String {
        val length = fieldLength(id)
        check(length in 0..4096) { "Invalid Faro metadata length" }
        return ByteArray(length) { offset ->
            val byte = fieldByte(id, offset)
            check(byte in 0..255) { "Invalid Faro metadata byte" }
            byte.toByte()
        }.toString(Charsets.UTF_8)
    }

    companion object {
        init {
            System.loadLibrary("faro_core")
        }
    }
}
