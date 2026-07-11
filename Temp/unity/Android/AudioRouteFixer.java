package nl.siwoc.internetradio;

import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioTrack;
import android.content.Context;

public class AudioRouteFixer {
    public static void retriggerAudioRouting(Context context) {
        try {
            // Simple volume poke to wake up AudioManager
            AudioManager am = (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);
            int vol = am.getStreamVolume(AudioManager.STREAM_MUSIC);
            am.setStreamVolume(AudioManager.STREAM_MUSIC, vol, 0);

            // Play brief silence to force audio routing re-evaluation
            AudioTrack silence = new AudioTrack(
                    new AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                            .build(),
                    new AudioFormat.Builder()
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .setSampleRate(44100)
                            .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                            .build(),
                    44100 * 2 * 1, // ~100 ms buffer
                    AudioTrack.MODE_STATIC,
                    AudioManager.AUDIO_SESSION_ID_GENERATE
            );

            byte[] data = new byte[4410 * 4]; // silence data
            silence.write(data, 0, data.length);
            silence.play();
            silence.stop();
            silence.release();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}

