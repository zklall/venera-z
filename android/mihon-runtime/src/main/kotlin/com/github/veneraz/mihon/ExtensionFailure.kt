package com.github.veneraz.mihon

fun Throwable.extensionCause(): Throwable {
    var current = this
    repeat(16) {
        val next = current.cause ?: return current
        if (next === current) return current
        current = next
    }
    return current
}
