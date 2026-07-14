package io.github.teamclouday.androidMic.utils

// helper function to ignore some exceptions
inline fun ignore(body: () -> Unit) {
    try {
        body()
    } catch (e: Exception) {
        e.printStackTrace()
    }
}


fun checkIp(ip: String): Boolean {
    val parts = ip.trim().split('.')
    return parts.size == 4 && parts.all { part ->
        part.isNotEmpty() && part.all(Char::isDigit) && part.toIntOrNull() in 0..255
    }
}

fun checkPort(portStr: String): Boolean {
    val port = portStr.toIntOrNull() ?: return false
    return port in 1..65535
}

fun Int.toBigEndianU32(): ByteArray {
    val unsigned = this.toLong() and 0xFFFFFFFFL

    val bytes = ByteArray(4)
    for (i in 0 until 4) {
        bytes[i] = (unsigned shr (24 - i * 8) and 0xFF).toByte()
    }

    return bytes
}

fun ByteArray.chunked(size: Int): List<ByteArray> {
    if (size <= 0) throw IllegalArgumentException("Size must be greater than 0")
    return (indices step size).map { start ->
        copyOfRange(start, (start + size).coerceAtMost(this.size))
    }
}

sealed class Either<out A, out B> {
    class Left<A>(val value: A) : Either<A, Nothing>()
    class Right<B>(val value: B) : Either<Nothing, B>()
}
