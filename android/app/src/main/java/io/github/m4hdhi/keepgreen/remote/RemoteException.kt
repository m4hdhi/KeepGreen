package io.github.m4hdhi.keepgreen.remote

/** A failed remote call. [message] is a friendly sentence that can be shown as-is. */
class RemoteException(
    override val message: String,
    val kind: Kind = Kind.Other,
    cause: Throwable? = null,
) : Exception(message, cause) {
    enum class Kind { Unreachable, BadCode, TooManyTries, NotTrusted, NotKeepGreen, Incompatible, BadResponse, Other }
}

/** Every sentence the remote client can show, in the same plain tone as the desktop app. */
object RemoteErrors {
    const val UNREACHABLE = "Couldn't reach the computer. Check it's on the same Wi-Fi and Phone remote is on."
    const val BAD_CODE = "Wrong or expired pairing code."
    const val TOO_MANY_TRIES = "Too many tries. Wait a minute and get a new code."
    const val NOT_TRUSTED =
        "The computer didn't accept this phone. Check the phone's clock is right, or remove the computer and pair it again."
    const val NOT_KEEPGREEN = "Something answered at that address, but it isn't KeepGreen."
    const val NEWER_DESKTOP = "This computer runs a newer KeepGreen. Update this app to control it."
    const val BAD_REQUEST = "The computer didn't understand the request. Update KeepGreen on both devices."
    const val INCOMPATIBLE = "This computer's KeepGreen can't do that. Update KeepGreen on both devices."
    const val BAD_RESPONSE = "The computer sent an answer this app doesn't understand."

    fun unexpected(code: Int) = "The computer answered with an error ($code). Try again in a moment."
}
