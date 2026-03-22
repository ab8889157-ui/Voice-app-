package com.voice.trick

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.arthenica.ffmpegkit.FFmpegKit
import com.arthenica.ffmpegkit.FFmpegKitConfig
import com.arthenica.ffmpegkit.ReturnCode
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    WhatsAppVoiceNoteScreen()
                }
            }
        }
    }
}

@Composable
fun WhatsAppVoiceNoteScreen() {
    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()

    var isConverting by remember { mutableStateOf(false) }
    var isReadyToShare by remember { mutableStateOf(false) }
    var timeLeft by remember { mutableStateOf(60) }
    var generatedFile by remember { mutableStateOf<File?>(null) }

    LaunchedEffect(isReadyToShare, timeLeft) {
        if (isReadyToShare && timeLeft > 0) {
            delay(1000L)
            timeLeft -= 1
        } else if (isReadyToShare && timeLeft == 0) {
            generatedFile?.delete()
            generatedFile = null
            isReadyToShare = false
            Toast.makeText(context, "انتهى الوقت! تم تدمير الملف لحماية مساحة الهاتف.", Toast.LENGTH_LONG).show()
        }
    }

    val audioPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetContent()
    ) { uri: Uri? ->
        uri?.let {
            isConverting = true
            isReadyToShare = false
            timeLeft = 60
            generatedFile?.delete()

            coroutineScope.launch(Dispatchers.IO) {
                val convertedFile = convertAudioToWhatsAppOpus(context, it)
                withContext(Dispatchers.Main) {
                    isConverting = false
                    if (convertedFile != null) {
                        generatedFile = convertedFile
                        isReadyToShare = true
                    } else {
                        Toast.makeText(context, "فشل تحويل الملف!", Toast.LENGTH_SHORT).show()
                    }
                }
            }
        }
    }

    Column(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Button(
            onClick = { audioPickerLauncher.launch("audio/*") },
            enabled = !isConverting
        ) {
            Text(if (isConverting) "جاري هندسة الصوت للواتساب..." else "1. اختر ملف صوتي")
        }

        Spacer(modifier = Modifier.height(32.dp))

        if (isReadyToShare && generatedFile != null) {
            val formattedTime = String.format("00:%02d", timeLeft)
            Text(
                text = "سيتم تدمير الملف بعد: $formattedTime",
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.titleMedium
            )

            Spacer(modifier = Modifier.height(16.dp))

            Button(
                onClick = { shareToWhatsApp(context, generatedFile!!) },
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF25D366))
            ) {
                Text("2. إرسال كرسالة صوتية خضراء (Voice Note)", color = Color.White)
            }
        }
    }
}

private fun convertAudioToWhatsAppOpus(context: Context, inputUri: Uri): File? {
    return try {
        val outputDir = File(context.cacheDir, "whatsapp_notes")
        if (!outputDir.exists()) outputDir.mkdirs()

        val outputFile = File(outputDir, "vn_${System.currentTimeMillis()}.ogg")
        val safInputPath = FFmpegKitConfig.getSafParameterForRead(context, inputUri)

        val command = "-y -i \"$safInputPath\" -c:a libopus -ar 16000 -ac 1 -b:a 32k \"${outputFile.absolutePath}\""
        val session = FFmpegKit.execute(command)

        if (ReturnCode.isSuccess(session.returnCode)) outputFile else null
    } catch (e: Exception) {
        e.printStackTrace()
        null
    }
}

private fun shareToWhatsApp(context: Context, file: File) {
    try {
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "audio/ogg"
            putExtra(Intent.EXTRA_STREAM, uri)
            setPackage("com.whatsapp")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(intent)
    } catch (e: Exception) {
        Toast.makeText(context, "تطبيق الواتساب غير مثبت!", Toast.LENGTH_SHORT).show()
    }
}