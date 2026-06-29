package com.suparpos.mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.content.Intent
import android.nfc.NdefMessage
import android.nfc.NdefRecord
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.tech.Ndef
import android.nfc.tech.NdefFormatable
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        const val ORDERS_CHANNEL_ID = "orders_urgent_v3"
    }

    private val channelName = "pos_foodscan/nfc_writer"
    private val deepLinkChannelName = "suparpos/deep_links"
    private var deepLinkChannel: MethodChannel? = null
    private var pendingDeepLink: String? = null
    private var nfcAdapter: NfcAdapter? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pendingPayload: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        pendingDeepLink = intent?.dataString
        super.onCreate(savedInstanceState)
        createOrdersNotificationChannel()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        nfcAdapter = NfcAdapter.getDefaultAdapter(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isNfcAvailable" -> {
                        val adapter = nfcAdapter
                        result.success(adapter != null && adapter.isEnabled)
                    }
                    "writeNfcTag" -> {
                        val payload = call.argument<String>("payload")
                        if (payload.isNullOrBlank()) {
                            result.error("EMPTY_PAYLOAD", "ไม่มีข้อมูลสำหรับเขียน NFC", null)
                        } else {
                            startNfcWrite(payload, result)
                        }
                    }
                    "cancelNfcWrite" -> {
                        cancelNfcWrite()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        deepLinkChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            deepLinkChannelName
        ).apply {
            setMethodCallHandler { call, result ->
                if (call.method == "getInitialLink") {
                    result.success(pendingDeepLink)
                    pendingDeepLink = null
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val link = intent.dataString ?: return
        pendingDeepLink = link
        deepLinkChannel?.invokeMethod("onLink", link)
    }

    private fun createOrdersNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            ORDERS_CHANNEL_ID,
            "SuparPOS Orders",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Order and payment alerts"
            val soundUri = Uri.parse("android.resource://$packageName/raw/foodscan_order")
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            setSound(soundUri, audioAttributes)
            enableVibration(true)
            setShowBadge(true)
        }

        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    override fun onPause() {
        super.onPause()
        if (pendingResult != null) {
            finishNfcWrite(errorCode = "CANCELLED", errorMessage = "ยกเลิกการเขียน NFC")
        }
    }

    private fun startNfcWrite(payload: String, result: MethodChannel.Result) {
        val adapter = nfcAdapter
        if (adapter == null) {
            result.error("NFC_UNAVAILABLE", "เครื่องนี้ไม่มี NFC", null)
            return
        }
        if (!adapter.isEnabled) {
            result.error("NFC_DISABLED", "กรุณาเปิด NFC ในเครื่องก่อน", null)
            return
        }
        if (pendingResult != null) {
            result.error("NFC_BUSY", "กำลังรอแท็ก NFC อยู่", null)
            return
        }

        pendingResult = result
        pendingPayload = payload

        val flags = NfcAdapter.FLAG_READER_NFC_A or
            NfcAdapter.FLAG_READER_NFC_B or
            NfcAdapter.FLAG_READER_NFC_F or
            NfcAdapter.FLAG_READER_NFC_V or
            NfcAdapter.FLAG_READER_NFC_BARCODE

        adapter.enableReaderMode(this, { tag ->
            writePayloadToTag(tag)
        }, flags, null)
    }

    private fun cancelNfcWrite() {
        if (pendingResult != null) {
            finishNfcWrite(errorCode = "CANCELLED", errorMessage = "ยกเลิกการเขียน NFC")
        } else {
            nfcAdapter?.disableReaderMode(this)
        }
    }

    private fun writePayloadToTag(tag: Tag) {
        val payload = pendingPayload ?: return
        val message = createNdefMessage(payload)

        try {
            val ndef = Ndef.get(tag)
            if (ndef != null) {
                ndef.connect()
                if (!ndef.isWritable) {
                    ndef.close()
                    finishNfcWrite(errorCode = "TAG_READ_ONLY", errorMessage = "แท็กนี้เขียนไม่ได้")
                    return
                }
                if (ndef.maxSize < message.toByteArray().size) {
                    ndef.close()
                    finishNfcWrite(errorCode = "TAG_TOO_SMALL", errorMessage = "แท็กนี้พื้นที่ไม่พอ")
                    return
                }
                ndef.writeNdefMessage(message)
                ndef.close()
                finishNfcWrite(successPayload = payload)
                return
            }

            val formatable = NdefFormatable.get(tag)
            if (formatable != null) {
                formatable.connect()
                formatable.format(message)
                formatable.close()
                finishNfcWrite(successPayload = payload)
                return
            }

            finishNfcWrite(errorCode = "UNSUPPORTED_TAG", errorMessage = "แท็กนี้ไม่รองรับ NDEF")
        } catch (e: Exception) {
            finishNfcWrite(errorCode = "WRITE_FAILED", errorMessage = e.localizedMessage ?: "เขียน NFC ไม่สำเร็จ")
        }
    }

    private fun createNdefMessage(payload: String): NdefMessage {
        val record = if (
            payload.startsWith("http://") ||
            payload.startsWith("https://") ||
            payload.contains("://")
        ) {
            NdefRecord.createUri(payload)
        } else {
            NdefRecord.createTextRecord("th", payload)
        }
        return NdefMessage(arrayOf(record))
    }

    private fun finishNfcWrite(
        successPayload: String? = null,
        errorCode: String? = null,
        errorMessage: String? = null
    ) {
        val result = pendingResult
        pendingResult = null
        pendingPayload = null
        runOnUiThread {
            nfcAdapter?.disableReaderMode(this)
            if (successPayload != null) {
                result?.success(successPayload)
            } else if (errorCode != null) {
                result?.error(errorCode, errorMessage, null)
            }
        }
    }
}
