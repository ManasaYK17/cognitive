#include <Arduino.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <I2S.h>
#include <SD.h>
#include <WebServer.h>
#include "esp_camera.h"
#include "camera_pins.h"
#include "secrets.h"

namespace {

constexpr uint32_t kIpPrintIntervalMs = 5000;
constexpr size_t kMinJpegBytes = 4000;     // suspiciously small -> likely blank frame
constexpr double kMinByteVariance = 300.0; // suspiciously flat -> likely blank/blurred
constexpr const char *kIdentifyUrl = "http://192.168.29.253:8000/api/recognition/identify-known-person/";
constexpr const char *kSummarizeUrl = "http://192.168.29.253:8000/api/conversations/summarize/";
constexpr const char *kTranscribeUrl = "http://192.168.29.253:8000/api/conversations/transcribe/";
constexpr const char *kCreateFromEncounterUrl = "http://192.168.29.253:8000/api/known-people/create-from-encounter/";
constexpr const char *kMultipartBoundary = "specsFirmwareBoundary";
// External INMP441 (standard I2S, not PDM) -- replaces the onboard PDM mic.
// Confirmed via pins_arduino.h: D0=GPIO1, D1=GPIO2, D3=GPIO4, none in
// conflict with camera/SD/the now-unused onboard mic pins (CLK=42/DATA=41).
constexpr int kMicSckPin = 1;  // D0 -- BCLK
constexpr int kMicWsPin = 2;   // D1 -- WS/LRCLK
constexpr int kMicSdPin = 4;   // D3 -- DATA (input); L/R tied to GND -> left channel only
// Required I2S slot width for the INMP441 (datasheet DS-INMP441-00: 24-bit
// data, MSB-justified, 32 SCK cycles per data-word) -- distinct from
// kWavBitsPerSample below, which is the *output WAV file's* format and stays
// 16-bit regardless of the hardware capture width.
constexpr int kI2sBitsPerSample = 32;
// This only throttles the status Serial print for visibility -- it has no
// effect on how often audio is actually read/written (see drainMicChunk,
// called unconditionally every loop() iteration in both states).
constexpr uint32_t kStatusPrintIntervalMs = 1000;
constexpr int kSdCsPin = 21;  // Onboard microSD CS (SCK=7/MISO=8/MOSI=9 are board SPI defaults)

constexpr uint32_t kWavSampleRate = 16000;
constexpr uint16_t kWavBitsPerSample = 16;
constexpr uint16_t kWavNumChannels = 1;

// Requested I2S sample rate is 2x the real target (kWavSampleRate) --
// compensates for a confirmed bug in I2SClass::_rx_done_routine() (I2S.cpp):
// single_dma_buf = _i2s_dma_buffer_size*(_bitsPerSample/8) omits the
// channel-count factor that the real per-DMA-buffer size includes (per
// driver/i2s.h's own doc: real_dma_buf_size = dma_buf_len*chan_num*
// bits_per_chan/8). For any 2-channel format -- which I2S_PHILIPS_MODE
// always is, per I2S.cpp's unconditional channel_format=
// I2S_CHANNEL_FMT_RIGHT_LEFT -- this reads exactly half of each real DMA
// buffer per RX_DONE event; with only 2 hardware buffer slots and no deeper
// queuing, the undrained half is silently overwritten, not just delayed.
// Confirmed via a live 45s recording: requesting 16000 measured an
// effective rate of 7787 (~49%, matching this exact 2x mechanism). Doubling
// the request should double real throughput too, landing the *measured*
// effective rate (what actually gets written to the WAV header -- see
// finalizeWavHeader()) close to the real 16000 target.
constexpr uint32_t kI2sRequestedSampleRate = kWavSampleRate * 2;

// No software gain for the INMP441 -- unlike the old onboard PDM mic (whose
// raw output sat too low in the int16 range without it), the INMP441's
// already-shifted (>>16) output landed cleanly on its own in the isolation
// test (silence ~300-1000, talking ~2000-4200, comfortably below the 32767
// ceiling) with no amplification. Confirmed on the integrated build too:
// reapplying the old PDM mic's 6x multiplier here pushed loud talking peaks
// close enough to the int16 ceiling to risk clipping, which compressed the
// silence/talking separation instead of helping it -- removed.

// Placeholder -- needs real-world calibration against this mic/enclosure/
// build (SD writing, enclosure acoustics, and real conversational distance
// all differ from the bare isolation-test wiring the underlying numbers
// came from). Peak amplitude threshold above which we consider "someone is
// talking". Recalibrated for the INMP441, un-gained -- NOT the old
// PDM-mic-tuned 4800 (which was scaled for 6x-amplified samples). Compared
// directly against the un-gained post->>16 samples in drainMicChunk().
// Set from a real quiet-vs-talking /status(livePeak) test on this exact
// integrated build (SD/camera/WiFi all active, gain removed): silence
// 171-328, talking 1134-2158 -- 700 sits with margin on both sides.
constexpr int16_t kNoiseFloor = 700;
// How far back the rolling duty-cycle window looks when deciding what
// fraction of recent chunks were above kNoiseFloor.
constexpr uint32_t kDutyCycleWindowMs = 2000;
// Generous headroom over the measured chunk rate (empirically ~60-65/sec at
// 16kHz/256-sample reads) so a 2-second window never overflows the buffer.
constexpr size_t kDutyCycleBufferCapacity = 512;
// Duty cycle (% of recent chunks above kNoiseFloor) must stay at/above this
// -- start low, tune from the live printed duty=%.1f%% values.
constexpr float kVoiceActivityDutyCycleThreshold = 40.0f;
// ...sustained continuously for this long to count as "conversation
// started", not just a brief loud burst nudging the ratio up momentarily.
constexpr uint32_t kVoiceActivityThresholdMs = 2000;
// Duty cycle must drop to/below this to end the recording -- also tune from
// the live printed values.
constexpr float kSilenceDutyCycleThreshold = 10.0f;
// ...sustained continuously for this long to end the recording. Placeholder
// value for testing -- real 30s/45-60s tuning later.
constexpr uint32_t kSilenceTimeoutMsPlaceholder = 10000;
// Placeholder -- real ~60s value comes later once the full identify-then-act
// flow is decided. Same pattern as kSilenceTimeoutMsPlaceholder above.
constexpr uint32_t kIdentifyDelayMsPlaceholder = 15000;
// HTTPClient's default (HTTPCLIENT_DEFAULT_TCP_TIMEOUT, HTTPClient.h) is
// only 5000ms -- an inactivity timeout on waiting for the server's
// response, confirmed too short for postConversationAudio(): uploading a
// multi-MB WAV plus the server's own transcribe_audio()/summarize_transcript()
// round-trips can easily exceed 5s even when nothing is actually hung. Sized
// for future longer conversations (real ~60s identify-delay + 45-60s
// silence-timeout will replace today's placeholders above), not just
// today's 88s test case. Capped at 60000: HTTPClient::setTimeout() takes a
// uint16_t, so anything above 65535 silently wraps -- 60000 is the largest
// clean round value safely under that ceiling.
constexpr uint16_t kConversationUploadTimeoutMs = 60000;

// The I2S ring buffer is only ~32ms deep (see drainMicChunk comment below).
// Any single loop() iteration blocking longer than this can overflow it
// regardless of how well drainMicChunk() itself then catches up.
constexpr uint32_t kSlowLoopIterationThresholdMs = 30;

enum class AppState { LISTENING, RECORDING };

AppState currentState = AppState::LISTENING;
uint32_t voiceActivityStartedAt = 0;  // 0 = not currently tracking a sustained-loud run
uint32_t silenceStartedAt = 0;        // 0 = not currently tracking a sustained-quiet run
bool identifyAttempted = false;       // per-RECORDING-session latch, reset in enterRecording()
bool lastIdentifyMatch = false;
String lastIdentifyName;
String lastIdentifyRelationship;
String lastIdentifySummary;
long lastIdentifyKnownPersonId = 0;  // "id" field from identify-known-person's response
long lastIdentifyPatientId = 0;      // "patient_id" field, same response (present regardless of match)
uint8_t *heldIdentifyImageBytes = nullptr;  // JPEG copied out of the mid-session capture, for a possible create-from-encounter upload in exitRecording()
size_t heldIdentifyImageLength = 0;
String warmup1ResultText = "not yet run";  // TEMP diagnostic, see /status
String warmup2ResultText = "not yet run";
bool cameraReady = false;
bool micReady = false;
bool sdReady = false;
File recordingFile;
uint32_t recordingBytesWritten = 0;
uint32_t totalBytesRead = 0;             // I2S.read() total during the open RECORDING session
uint32_t recordingChunkCount = 0;        // count of I2S.read() calls that returned data, same session
uint32_t recordingSessionStartedAtMs = 0;
int16_t recordingPeakSinceLastPrint = 0;
int recordingFileCounter = 0;
String currentRecordingFilename;
String latestClosedRecordingFilename;

// TEMP diagnostic: captures the fully raw, interleaved 32-bit I2S stream
// (both Left and Right slots, before the >>16 shift, before de-interleave,
// before the carry-buffer reassembly's consumers ever see it) straight to
// SD -- isolates whether corruption exists in the physical I2S stream
// itself versus somewhere in this code's processing pipeline. Independent
// of the main recording pipeline entirely (separate file, separate trigger,
// never touches recordingFile/currentRecordingFilename).
bool rawCaptureActive = false;
File rawCaptureFile;
uint32_t rawCaptureBytesRemaining = 0;
// Widened from an earlier ~4s budget: the trigger-then-ask-user-to-talk
// round trip has enough human reaction-time lag that a short window kept
// closing before real speech started, capturing mostly lead-in silence.
// ~12s at real throughput gives comfortable margin either way.
constexpr uint32_t kRawCaptureBytesBudget = 1500000;

// Rolling duty-cycle tracking: a circular buffer of (timestamp, aboveFloor)
// samples, one per real chunk read from the mic, covering the last
// kDutyCycleWindowMs. dutyCycleAboveCount is maintained incrementally so
// computing the current percentage is O(1) rather than rescanning the
// buffer every loop() iteration.
struct DutyCycleSample {
  uint32_t timestampMs;
  bool aboveFloor;
};
DutyCycleSample dutyCycleBuffer[kDutyCycleBufferCapacity];
size_t dutyCycleHead = 0;
size_t dutyCycleCount = 0;
size_t dutyCycleAboveCount = 0;

// Rate-measurement counters, reset every status print (~1s).
uint32_t loopCallsSinceLastPrint = 0;   // how many loop() iterations ran
uint32_t realChunksSinceLastPrint = 0;  // how many real 256-sample chunks were drained (can exceed loopCallsSinceLastPrint when a call catches up on backlog)

// loop() iteration timing, reset every status print (~1s).
uint32_t maxLoopIterationUs = 0;      // longest single iteration observed
uint32_t slowLoopIterationCount = 0;  // iterations exceeding kSlowLoopIterationThresholdMs

WebServer server(80);

camera_config_t buildCameraConfig() {
  camera_config_t config = {};
  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_sccb_sda = SIOD_GPIO_NUM;
  config.pin_sccb_scl = SIOC_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.xclk_freq_hz = 20000000;
  config.ledc_timer = LEDC_TIMER_0;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.pixel_format = PIXFORMAT_JPEG;
  config.frame_size = FRAMESIZE_VGA;
  config.jpeg_quality = 10;
  config.fb_count = psramFound() ? 2 : 1;
  config.fb_location = psramFound() ? CAMERA_FB_IN_PSRAM : CAMERA_FB_IN_DRAM;
  config.grab_mode = CAMERA_GRAB_LATEST;
  return config;
}

bool initCamera() {
  camera_config_t config = buildCameraConfig();
  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("Camera init failed (error 0x%x)\n", err);
    return false;
  }
  return true;
}

camera_fb_t *captureOneFrame() {
  camera_fb_t *fb = esp_camera_fb_get();
  if (!fb) {
    Serial.println("Camera capture failed.");
    return nullptr;
  }
  Serial.printf("Captured JPEG frame: %u bytes\n", fb->len);
  return fb;
}

// TEMP diagnostic: a discarded warm-up capture, timed, to isolate whether
// the mid-RECORDING capture failure (8s esp_camera_fb_get() stall) is
// caused by camera coldness (first-ever capture) or by concurrent I2S mic
// activity. Called twice from setup() with different labels -- once before
// initMic() (mic not yet active) and once right after (mic active, as it
// will be for the rest of the device's life).
// Returns a one-line summary so the result survives (in warmup1ResultText /
// warmup2ResultText, served over HTTP by handleStatus()) regardless of
// whether a serial monitor was attached in time to see the live line.
String runWarmupCapture(const char *label) {
  Serial.printf("[WARMUP %s] starting...\n", label);
  uint32_t startMs = millis();
  camera_fb_t *fb = captureOneFrame();
  uint32_t elapsedMs = millis() - startMs;
  String result;
  if (fb) {
    result = String("succeeded: ") + fb->len + " bytes, took " + elapsedMs + "ms";
    esp_camera_fb_return(fb);
  } else {
    result = String("failed (esp_camera_fb_get() returned null), took ") + elapsedMs + "ms";
  }
  Serial.printf("[WARMUP %s] %s\n", label, result.c_str());
  return result;
}

// Deinit+reinit the camera immediately before capturing. Confirmed via
// prior /status-tracked testing to reliably recover capture capability
// under the one condition that reliably breaks a direct esp_camera_fb_get()
// call: mic actively running via I2S, deep into a RECORDING session.
// Touches only the camera -- I2S/mic and SD are never touched. Returns
// nullptr if either the reinit or the capture itself fails; the camera is
// left initialized (holding the frame buffer) on success so the caller can
// use fb->buf/fb->len before returning it and deiniting.
camera_fb_t *captureFrameViaReinit() {
  esp_camera_deinit();
  camera_config_t config = buildCameraConfig();
  esp_err_t initErr = esp_camera_init(&config);
  if (initErr != ESP_OK) {
    Serial.printf("[IDENTIFY] camera reinit failed (error 0x%x)\n", initErr);
    return nullptr;
  }
  return captureOneFrame();
}

bool identifyKnownPerson(camera_fb_t *fb, String &outName, String &outRelationship, String &outLastSummary,
                          long &outKnownPersonId, long &outPatientId) {
  String bodyStart = String("--") + kMultipartBoundary + "\r\n" +
                      "Content-Disposition: form-data; name=\"image\"; filename=\"capture.jpg\"\r\n" +
                      "Content-Type: image/jpeg\r\n\r\n";
  String bodyEnd = String("\r\n--") + kMultipartBoundary + "--\r\n";
  size_t totalLen = bodyStart.length() + fb->len + bodyEnd.length();

  // The JPEG can be tens to ~150KB (UXGA); prefer PSRAM for this scratch
  // buffer so it doesn't compete with the small internal heap.
  uint8_t *body = psramFound() ? (uint8_t *)ps_malloc(totalLen) : (uint8_t *)malloc(totalLen);
  if (!body) {
    Serial.println("Failed to allocate request buffer.");
    return false;
  }

  size_t offset = 0;
  memcpy(body + offset, bodyStart.c_str(), bodyStart.length());
  offset += bodyStart.length();
  memcpy(body + offset, fb->buf, fb->len);
  offset += fb->len;
  memcpy(body + offset, bodyEnd.c_str(), bodyEnd.length());

  HTTPClient http;
  http.begin(kIdentifyUrl);
  http.addHeader("Content-Type", String("multipart/form-data; boundary=") + kMultipartBoundary);
  http.addHeader("Authorization", String("Bearer ") + PATIENT_SESSION_TOKEN);

  int httpCode = http.POST(body, totalLen);
  free(body);

  if (httpCode <= 0) {
    Serial.printf("HTTP request failed: %s\n", http.errorToString(httpCode).c_str());
    http.end();
    return false;
  }

  String response = http.getString();
  http.end();
  Serial.printf("HTTP response code: %d\n", httpCode);

  JsonDocument doc;
  DeserializationError parseErr = deserializeJson(doc, response);
  if (parseErr) {
    Serial.printf("Failed to parse JSON response: %s\n", parseErr.c_str());
    return false;
  }

  bool match = doc["match"] | false;
  const char *name = doc["name"] | "(none)";
  const char *relationship = doc["relationship"] | "(none)";
  const char *lastSummary = doc["last_summary"] | "(none)";
  long knownPersonId = doc["id"] | 0L;    // null in JSON when no match -- defaults to 0
  long patientId = doc["patient_id"] | 0L;

  Serial.printf("match: %s\n", match ? "true" : "false");
  Serial.printf("name: %s\n", name);
  Serial.printf("relationship: %s\n", relationship);
  Serial.printf("last_summary: %s\n", lastSummary);
  Serial.printf("id: %ld\n", knownPersonId);
  Serial.printf("patient_id: %ld\n", patientId);

  outName = name;
  outRelationship = relationship;
  outLastSummary = lastSummary;
  outKnownPersonId = knownPersonId;
  outPatientId = patientId;
  return match;
}

// Concatenates a small in-memory preamble, a File's contents, and a small
// in-memory epilogue into one continuous byte stream -- lets HTTPClient's
// sendRequest(type, Stream*, size) POST a multipart body containing a large
// file (the WAV, which can run into multiple MB) without ever buffering the
// whole file in RAM, unlike the small-JPEG multipart bodies built directly
// in memory elsewhere (identifyKnownPerson(), postCreateFromEncounter()).
class MultipartFileStream : public Stream {
 public:
  MultipartFileStream(const String &preamble, File &file, const String &epilogue)
      : preamble_(preamble), file_(file), epilogue_(epilogue) {}

  int available() override {
    return (int)((preamble_.length() - preambleIndex_) + file_.available() + (epilogue_.length() - epilogueIndex_));
  }

  int read() override {
    if (preambleIndex_ < preamble_.length()) return (uint8_t)preamble_[preambleIndex_++];
    if (file_.available()) {
      int b = file_.read();
      if (b >= 0) fileBytesServed_++;
      return b;
    }
    if (epilogueIndex_ < epilogue_.length()) return (uint8_t)epilogue_[epilogueIndex_++];
    return -1;
  }

  int peek() override {
    if (preambleIndex_ < preamble_.length()) return (uint8_t)preamble_[preambleIndex_];
    if (file_.available()) return file_.peek();
    if (epilogueIndex_ < epilogue_.length()) return (uint8_t)epilogue_[epilogueIndex_];
    return -1;
  }

  size_t write(uint8_t) override { return 0; }  // read-only stream; Stream/Print require an override

  // Bytes actually served from the file_ segment specifically (excludes
  // preamble/epilogue) -- every byte HTTPClient consumes funnels through
  // read() above (confirmed via Stream::readBytes() -> timedRead() ->
  // read(), in the installed core's Stream.cpp), so this is an exact count
  // of what got sent, not an estimate.
  size_t fileBytesServed() const { return fileBytesServed_; }

 private:
  String preamble_;
  size_t preambleIndex_ = 0;
  File &file_;
  String epilogue_;
  size_t epilogueIndex_ = 0;
  size_t fileBytesServed_ = 0;
};

// Posts an already-closed WAV file (streamed directly from SD via
// MultipartFileStream, never buffered whole) as multipart field "audio",
// plus patient_id and (optionally) known_person_id -- the shared shape of
// /api/conversations/summarize/ and /api/conversations/transcribe/. Returns
// the HTTP status code (<=0 on transport failure) and fills
// outTranscript/outSummary from the JSON response when parseable.
int postConversationAudio(const char *url, const String &filename, long patientId, long knownPersonId,
                           bool includeKnownPersonId, String &outTranscript, String &outSummary) {
  File file = SD.open(filename, FILE_READ);
  if (!file) {
    Serial.printf("[UPLOAD] Failed to open %s for upload to %s\n", filename.c_str(), url);
    return 0;
  }

  String preamble = String("--") + kMultipartBoundary + "\r\n" +
                     "Content-Disposition: form-data; name=\"patient_id\"\r\n\r\n" +
                     String(patientId) + "\r\n";
  if (includeKnownPersonId) {
    preamble += String("--") + kMultipartBoundary + "\r\n" +
                "Content-Disposition: form-data; name=\"known_person_id\"\r\n\r\n" +
                String(knownPersonId) + "\r\n";
  }
  preamble += String("--") + kMultipartBoundary + "\r\n" +
              "Content-Disposition: form-data; name=\"audio\"; filename=\"recording.wav\"\r\n" +
              "Content-Type: audio/wav\r\n\r\n";
  String epilogue = String("\r\n--") + kMultipartBoundary + "--\r\n";

  size_t fileSizeBytes = file.size();
  size_t totalLen = preamble.length() + fileSizeBytes + epilogue.length();
  MultipartFileStream bodyStream(preamble, file, epilogue);

  HTTPClient http;
  http.begin(url);
  http.setTimeout(kConversationUploadTimeoutMs);
  http.addHeader("Content-Type", String("multipart/form-data; boundary=") + kMultipartBoundary);
  http.addHeader("Authorization", String("Bearer ") + PATIENT_SESSION_TOKEN);

  int httpCode = http.sendRequest("POST", &bodyStream, totalLen);
  file.close();

  // Ground-truth check on the streaming implementation itself, independent
  // of whatever HTTP status comes back: does the WAV-portion byte count the
  // stream actually served match the file's real size on disk? (The file
  // size itself should be recordingBytesWritten+44 for the WAV header --
  // logged alongside for a manual cross-check, not compared directly, since
  // recordingBytesWritten excludes the header.)
  Serial.printf("[UPLOAD] %s: WAV bytes streamed=%u, file size on disk=%u, recordingBytesWritten=%u (expect file size == recordingBytesWritten+44)\n",
                url, (unsigned)bodyStream.fileBytesServed(), (unsigned)fileSizeBytes, (unsigned)recordingBytesWritten);
  if (bodyStream.fileBytesServed() != fileSizeBytes) {
    Serial.println("[UPLOAD] MISMATCH: MultipartFileStream did not stream the full file -- streaming bug.");
  }

  if (httpCode <= 0) {
    Serial.printf("[UPLOAD] %s request failed: %s\n", url, http.errorToString(httpCode).c_str());
    http.end();
    return httpCode;
  }

  String response = http.getString();
  http.end();
  Serial.printf("[UPLOAD] %s HTTP response code: %d\n", url, httpCode);

  JsonDocument doc;
  DeserializationError parseErr = deserializeJson(doc, response);
  if (parseErr) {
    Serial.printf("[UPLOAD] Failed to parse JSON response from %s: %s\n", url, parseErr.c_str());
    return httpCode;
  }

  const char *transcript = doc["transcript"] | "";
  const char *summary = doc["summary"] | "";
  const char *errorMessage = doc["error_message"] | nullptr;
  outTranscript = transcript;
  outSummary = summary;
  if (errorMessage) {
    Serial.printf("[UPLOAD] %s reported error_message: %s\n", url, errorMessage);
  }
  return httpCode;
}

// Small in-memory multipart body (unlike postConversationAudio()'s streamed
// approach) since the held JPEG is tens of KB, not megabytes -- same
// buffering pattern identifyKnownPerson() already uses.
bool postCreateFromEncounter(const uint8_t *imageBytes, size_t imageLength, const String &summary, long patientId) {
  String bodyStart = String("--") + kMultipartBoundary + "\r\n" +
                      "Content-Disposition: form-data; name=\"patient_id\"\r\n\r\n" +
                      String(patientId) + "\r\n" +
                      "--" + kMultipartBoundary + "\r\n" +
                      "Content-Disposition: form-data; name=\"summary\"\r\n\r\n" +
                      summary + "\r\n" +
                      "--" + kMultipartBoundary + "\r\n" +
                      "Content-Disposition: form-data; name=\"files\"; filename=\"encounter.jpg\"\r\n" +
                      "Content-Type: image/jpeg\r\n\r\n";
  String bodyEnd = String("\r\n--") + kMultipartBoundary + "--\r\n";
  size_t totalLen = bodyStart.length() + imageLength + bodyEnd.length();

  uint8_t *body = psramFound() ? (uint8_t *)ps_malloc(totalLen) : (uint8_t *)malloc(totalLen);
  if (!body) {
    Serial.println("[UPLOAD] Failed to allocate request buffer for create-from-encounter.");
    return false;
  }

  size_t offset = 0;
  memcpy(body + offset, bodyStart.c_str(), bodyStart.length());
  offset += bodyStart.length();
  memcpy(body + offset, imageBytes, imageLength);
  offset += imageLength;
  memcpy(body + offset, bodyEnd.c_str(), bodyEnd.length());

  HTTPClient http;
  http.begin(kCreateFromEncounterUrl);
  http.addHeader("Content-Type", String("multipart/form-data; boundary=") + kMultipartBoundary);
  http.addHeader("Authorization", String("Bearer ") + PATIENT_SESSION_TOKEN);

  int httpCode = http.POST(body, totalLen);
  free(body);

  if (httpCode <= 0) {
    Serial.printf("[UPLOAD] create-from-encounter request failed: %s\n", http.errorToString(httpCode).c_str());
    http.end();
    return false;
  }

  Serial.printf("[UPLOAD] create-from-encounter HTTP response code: %d\n", httpCode);
  http.end();
  return httpCode >= 200 && httpCode < 300;
}

// Cheap, approximate signal -- NOT real face detection or blur detection.
// Computed directly on the compressed JPEG byte stream rather than decoded
// pixels: a near-blank or heavily blurred scene has little high-frequency
// detail, so JPEG compresses it into long runs of similar bytes, which
// shows up as low variance in the raw stream itself. Sampling every 8th
// byte keeps this fast enough to run every cycle.
double frameByteVariance(const camera_fb_t *fb) {
  constexpr size_t kSampleStride = 8;
  double mean = 0.0;
  size_t sampleCount = 0;
  for (size_t i = 0; i < fb->len; i += kSampleStride) {
    mean += fb->buf[i];
    sampleCount++;
  }
  mean /= sampleCount;

  double variance = 0.0;
  for (size_t i = 0; i < fb->len; i += kSampleStride) {
    double diff = fb->buf[i] - mean;
    variance += diff * diff;
  }
  variance /= sampleCount;
  return variance;
}

bool looksUsable(const camera_fb_t *fb, double variance) {
  return fb->len >= kMinJpegBytes && variance >= kMinByteVariance;
}

bool runCaptureCycle() {
  camera_fb_t *fb = captureOneFrame();
  if (!fb) {
    Serial.printf("[%lu ms] skipped: capture failed\n", millis());
    return false;
  }

  double variance = frameByteVariance(fb);
  bool usable = looksUsable(fb, variance);
  Serial.printf("[%lu ms] variance=%.1f bytes=%u -> %s\n", millis(), variance, fb->len,
                usable ? "uploaded" : "skipped");

  if (!usable) {
    esp_camera_fb_return(fb);
    return false;
  }

  String unusedName, unusedRelationship, unusedLastSummary;
  long unusedKnownPersonId, unusedPatientId;
  bool matched = identifyKnownPerson(fb, unusedName, unusedRelationship, unusedLastSummary,
                                      unusedKnownPersonId, unusedPatientId);
  esp_camera_fb_return(fb);
  return matched;
}

bool initMic() {
  I2S.setAllPins(kMicSckPin, kMicWsPin, kMicSdPin, -1, -1);
  // I2S_PHILIPS_MODE: the INMP441 is a standard-I2S mic, not PDM. Confirmed
  // as the library's only officially-supported non-PDM mode (log_w at
  // I2S.cpp:262) and matching the datasheet's stated default data format.
  // Requesting kI2sRequestedSampleRate (2x kWavSampleRate) -- see its
  // comment above for the exact confirmed library bug this compensates for.
  if (!I2S.begin(I2S_PHILIPS_MODE, kI2sRequestedSampleRate, kI2sBitsPerSample)) {
    Serial.println("Mic init failed.");
    return false;
  }
  // Stream::available() is the only rate-adjacent stat this library exposes
  // (no direct "effective sample rate" getter) -- printed as-is so we can
  // see whether the driver already has a backlog immediately after begin().
  Serial.printf("I2S.available() right after begin(): %d\n", I2S.available());
  return true;
}

bool initSd() {
  // SCK/MISO/MOSI already match this board's default SPI pins (7/8/9), so
  // SD.begin() only needs the CS pin -- SDFS::begin() calls SPI.begin()
  // internally with those board defaults.
  if (!SD.begin(kSdCsPin)) {
    Serial.println("SD card init failed.");
    return false;
  }
  return true;
}

// Writes a 44-byte canonical PCM WAV header with placeholder size fields
// (both patched in by finalizeWavHeader() once the real byte count is
// known, on exiting RECORDING).
void writeWavHeaderPlaceholder(File &file) {
  uint32_t byteRate = kWavSampleRate * kWavNumChannels * (kWavBitsPerSample / 8);
  uint16_t blockAlign = kWavNumChannels * (kWavBitsPerSample / 8);
  uint32_t placeholder32 = 0;
  uint16_t audioFormatPcm = 1;
  uint32_t subchunk1Size = 16;

  file.write((const uint8_t *)"RIFF", 4);
  file.write((const uint8_t *)&placeholder32, 4);  // ChunkSize, patched later
  file.write((const uint8_t *)"WAVE", 4);
  file.write((const uint8_t *)"fmt ", 4);
  file.write((const uint8_t *)&subchunk1Size, 4);
  file.write((const uint8_t *)&audioFormatPcm, 2);
  file.write((const uint8_t *)&kWavNumChannels, 2);
  file.write((const uint8_t *)&kWavSampleRate, 4);
  file.write((const uint8_t *)&byteRate, 4);
  file.write((const uint8_t *)&blockAlign, 2);
  file.write((const uint8_t *)&kWavBitsPerSample, 2);
  file.write((const uint8_t *)"data", 4);
  file.write((const uint8_t *)&placeholder32, 4);  // Subchunk2Size, patched later
}

// Seeks back into the already-written header and fills in everything that
// could not be known until recording ended: the two size fields, and the
// sample-rate/byte-rate fields (offsets 24/28), overwriting whatever
// writeWavHeaderPlaceholder() wrote there. effectiveSampleRate comes from
// measuring actual bytes-written-per-actual-second, not the sampleRate
// requested from I2S.begin() -- so the header reflects reality regardless
// of what the driver actually delivers.
void finalizeWavHeader(File &file, uint32_t dataBytes, uint32_t effectiveSampleRate) {
  uint32_t chunkSize = 36 + dataBytes;
  file.seek(4);
  file.write((const uint8_t *)&chunkSize, 4);

  uint32_t effectiveByteRate = effectiveSampleRate * kWavNumChannels * (kWavBitsPerSample / 8);
  file.seek(24);
  file.write((const uint8_t *)&effectiveSampleRate, 4);
  file.seek(28);
  file.write((const uint8_t *)&effectiveByteRate, 4);

  file.seek(40);
  file.write((const uint8_t *)&dataBytes, 4);
}

void evictExpiredDutyCycleSamples(uint32_t now) {
  size_t tail = (dutyCycleHead + kDutyCycleBufferCapacity - dutyCycleCount) % kDutyCycleBufferCapacity;
  while (dutyCycleCount > 0 && (now - dutyCycleBuffer[tail].timestampMs) > kDutyCycleWindowMs) {
    if (dutyCycleBuffer[tail].aboveFloor) dutyCycleAboveCount--;
    dutyCycleCount--;
    tail = (tail + 1) % kDutyCycleBufferCapacity;
  }
}

void recordDutyCycleSample(uint32_t now, bool aboveFloor) {
  evictExpiredDutyCycleSamples(now);
  if (dutyCycleCount == kDutyCycleBufferCapacity) {
    // Shouldn't normally happen given the capacity headroom, but don't
    // overflow if the real chunk rate is far higher than expected.
    size_t tail = (dutyCycleHead + kDutyCycleBufferCapacity - dutyCycleCount) % kDutyCycleBufferCapacity;
    if (dutyCycleBuffer[tail].aboveFloor) dutyCycleAboveCount--;
    dutyCycleCount--;
  }
  dutyCycleBuffer[dutyCycleHead] = {now, aboveFloor};
  if (aboveFloor) dutyCycleAboveCount++;
  dutyCycleHead = (dutyCycleHead + 1) % kDutyCycleBufferCapacity;
  dutyCycleCount++;
}

float currentDutyCyclePercent() {
  if (dutyCycleCount == 0) return 0.0f;
  return (100.0f * dutyCycleAboveCount) / dutyCycleCount;
}

// Drains every full chunk currently sitting in the I2S ring buffer, not
// just one -- so a single call (and therefore a single loop() iteration)
// catches up on however much has built up since the last one, regardless
// of loop()'s own call rate. Must be called on every loop() iteration with
// no interval gate, in BOTH states: the ring buffer holds only ~32ms of
// audio (128 frames x 2 DMA buffers x 2 bytes/sample x 2, per I2S.cpp), so
// anything slower risks silently dropping audio at the driver level -- and
// LISTENING needs continuous audio to detect sustained voice activity in
// the first place, not just RECORDING.
//
// I2S.available() (I2S.cpp: _buffer_byte_size - xRingbufferGetCurFreeSize
// (_input_ring_buffer)) is a genuinely non-blocking bytes-ready query -- it
// never calls into read()'s xRingbufferReceiveUpTo() or its internal 1000ms
// timeout. Gating every read() behind "a full chunk is already sitting
// there" guarantees read() always has its whole request ready and returns
// immediately, instead of a naive "loop read() until 0" drain risking a
// multi-second stall the moment the buffer runs dry mid-loop. The loop
// stops the instant less than one full chunk remains available; that
// remainder stays in the ring buffer for the next call to pick up rather
// than forcing a short read of it now.
//
// Reads raw 32-bit I2S words, not the final 16-bit WAV samples directly.
// Confirmed via I2S.cpp's _installDriver(): I2S_PHILIPS_MODE is not in the
// library's mono-clock-config branch (only I2S_RIGHT_JUSTIFIED_MODE,
// I2S_LEFT_JUSTIFIED_MODE, and PDM_MONO_MODE get i2s_set_clk(...,
// I2S_CHANNEL_MONO)) -- Philips mode stays full stereo
// (channel_format is unconditionally I2S_CHANNEL_FMT_RIGHT_LEFT), so every
// WS cycle clocks in a Left slot and a Right slot, interleaved in the read
// buffer. This INMP441 has L/R tied to GND (left channel only) -- the Right
// slot is undriven/floating bus noise, so every other raw sample is
// discarded below, keeping only the Left slot, per standard WS-low-starts-
// left I2S framing (validated against the isolation test's quiet/talk
// numbers).
//
// L/R pairing is carried across calls via carryBytes/carryLen, not assumed
// to restart cleanly at index 0 every call. Confirmed via I2S.cpp:
// I2SClass::read() fetches from the ring buffer through
// xRingbufferReceiveUpTo(), which -- per documented FreeRTOS/ESP-IDF
// byte-ringbuffer behavior -- can return fewer bytes than requested
// whenever the read would cross the buffer's physical wrap point. A short
// read not landing on an 8-byte (one L+R pair) boundary would otherwise
// silently flip which raw samples this code treats as "Left" for every
// sample after that point, scrambling real captured audio at the sample
// level while leaving aggregate amplitude/spectral stats looking plausible.
void drainMicChunk(uint32_t now) {
  constexpr size_t kRawSampleCount = 256;
  constexpr size_t kRawBufferBytes = kRawSampleCount * sizeof(int32_t);
  static uint8_t carryBytes[8];
  static size_t carryLen = 0;
  uint8_t readBuf[kRawBufferBytes];
  static uint8_t combined[kRawBufferBytes + 8];
  int16_t outSamples[kRawSampleCount / 2];  // de-interleaved (Left-only), shifted to 16-bit range

  while (I2S.available() >= (int)kRawBufferBytes) {
    int got = I2S.read(readBuf, kRawBufferBytes);
    if (got <= 0) break;  // shouldn't happen given the guard above, but don't spin if it does

    size_t combinedLen = carryLen;
    if (carryLen > 0) memcpy(combined, carryBytes, carryLen);
    memcpy(combined + combinedLen, readBuf, (size_t)got);
    combinedLen += (size_t)got;

    size_t completeBytes = (combinedLen / 8) * 8;  // whole L/R pairs only
    carryLen = combinedLen - completeBytes;
    if (carryLen > 0) memcpy(carryBytes, combined + completeBytes, carryLen);

    int32_t *rawSamples = (int32_t *)combined;
    size_t rawSamplesRead = completeBytes / sizeof(int32_t);

    // TEMP diagnostic tap: writes the exact bytes about to be shifted/
    // de-interleaved below, completely unmodified -- see rawCaptureActive's
    // declaration comment.
    if (rawCaptureActive && rawCaptureFile && completeBytes > 0) {
      size_t toWrite = completeBytes;
      if (toWrite > rawCaptureBytesRemaining) toWrite = rawCaptureBytesRemaining;
      if (toWrite > 0) {
        rawCaptureFile.write((const uint8_t *)combined, toWrite);
        rawCaptureBytesRemaining -= toWrite;
      }
      if (rawCaptureBytesRemaining == 0) {
        rawCaptureFile.close();
        rawCaptureActive = false;
      }
    }

    size_t outCount = 0;
    int16_t peak = 0;
    for (size_t i = 0; i < rawSamplesRead; i += 2) {  // Left slot only -- see de-interleave comment above
      // >>16 total: >>8 takes the raw 32-bit word down to the true 24-bit
      // signed value (datasheet's MSB-justified 24-in-32 framing), then >>8
      // more truncates 24-bit -> 16-bit (standard bit-depth reduction: keep
      // the top 16 of the 24 significant bits). No gain multiply -- this
      // already lands cleanly within int16 range on its own (see kNoiseFloor
      // comment above); clamp kept only as a cheap guard against a shifted
      // value landing exactly at INT32_MIN, whose absolute value would
      // otherwise overflow int16_t.
      int32_t shifted = rawSamples[i] >> 16;
      if (shifted > INT16_MAX) shifted = INT16_MAX;
      if (shifted < INT16_MIN) shifted = INT16_MIN;
      int16_t sampleOut = (int16_t)shifted;
      outSamples[outCount++] = sampleOut;

      int16_t absSample = sampleOut < 0 ? (int16_t)(-sampleOut) : sampleOut;
      if (absSample > peak) peak = absSample;
      if (absSample > recordingPeakSinceLastPrint) recordingPeakSinceLastPrint = absSample;
    }

    size_t outBytes = outCount * sizeof(int16_t);
    if (recordingFile) {
      totalBytesRead += outBytes;
      recordingChunkCount++;
      size_t written = recordingFile.write((const uint8_t *)outSamples, outBytes);
      recordingBytesWritten += written;
    }

    recordDutyCycleSample(now, peak >= kNoiseFloor);
    realChunksSinceLastPrint++;
  }
}

// Purely for visibility -- throttled separately from drainMicChunk() so
// the read/write cadence above is never gated by this. Shows everything
// needed to calibrate kNoiseFloor/kVoiceActivityDutyCycleThreshold/
// kSilenceDutyCycleThreshold against real data instead of guessing blind.
void printStatus(float dutyCyclePercent) {
  Serial.printf("chunks/s=%lu real/s=%lu duty=%.1f%% peak=%d maxIterUs=%lu slowIters=%lu\n",
                (unsigned long)loopCallsSinceLastPrint, (unsigned long)realChunksSinceLastPrint,
                dutyCyclePercent, recordingPeakSinceLastPrint,
                (unsigned long)maxLoopIterationUs, (unsigned long)slowLoopIterationCount);
  loopCallsSinceLastPrint = 0;
  realChunksSinceLastPrint = 0;
  recordingPeakSinceLastPrint = 0;
  maxLoopIterationUs = 0;
  slowLoopIterationCount = 0;
}

// Called at every loop() exit point so slow iterations are caught
// regardless of which return path was taken (e.g. the early !micReady
// return still includes server.handleClient() overhead).
void recordLoopIterationDuration(uint32_t iterationStartUs) {
  uint32_t elapsedUs = micros() - iterationStartUs;
  if (elapsedUs > maxLoopIterationUs) maxLoopIterationUs = elapsedUs;
  if (elapsedUs > kSlowLoopIterationThresholdMs * 1000UL) slowLoopIterationCount++;
}

void setState(AppState newState) {
  currentState = newState;
  Serial.print("[STATE] ");
  Serial.println(newState == AppState::LISTENING ? "LISTENING" : "RECORDING");
}

void enterRecording() {
  // Mic is already running continuously (initialized once in setup(), never
  // torn down) -- nothing to (re)initialize here, just start writing.
  recordingBytesWritten = 0;
  totalBytesRead = 0;
  recordingChunkCount = 0;
  recordingSessionStartedAtMs = millis();
  identifyAttempted = false;
  // Reset every session so a failed/skipped identify attempt this session
  // can never fall back to a stale result from a previous one when
  // exitRecording() decides which backend upload path to take.
  lastIdentifyMatch = false;
  lastIdentifyName = "";
  lastIdentifyRelationship = "";
  lastIdentifySummary = "";
  lastIdentifyKnownPersonId = 0;
  lastIdentifyPatientId = 0;
  if (sdReady) {
    currentRecordingFilename = "/rec_" + String(recordingFileCounter++) + ".wav";
    recordingFile = SD.open(currentRecordingFilename, FILE_WRITE);
    if (recordingFile) {
      writeWavHeaderPlaceholder(recordingFile);
      Serial.printf("Recording to %s\n", currentRecordingFilename.c_str());
    } else {
      Serial.printf("Failed to open %s for writing.\n", currentRecordingFilename.c_str());
    }
  }

  silenceStartedAt = 0;
  setState(AppState::RECORDING);
}

void exitRecording() {
  if (recordingFile) {
    uint32_t durationMs = millis() - recordingSessionStartedAtMs;
    // Measured, not requested: real bytes actually written divided by real
    // elapsed time, so the header is correct regardless of what sample rate
    // the I2S/PDM driver actually delivers versus what was requested.
    double effectiveRateExact =
        durationMs > 0 ? (double)totalBytesRead / (durationMs / 1000.0) / (kWavBitsPerSample / 8)
                        : (double)kWavSampleRate;
    uint32_t effectiveSampleRate = (uint32_t)(effectiveRateExact + 0.5);

    finalizeWavHeader(recordingFile, recordingBytesWritten, effectiveSampleRate);
    recordingFile.close();
    latestClosedRecordingFilename = currentRecordingFilename;
    float avgBytesPerChunk = recordingChunkCount > 0 ? (float)totalBytesRead / recordingChunkCount : 0.0f;
    Serial.printf("Recording closed: durationMs=%u totalBytesRead=%u bytesWritten=%u chunkCount=%u avgBytesPerChunk=%.1f effectiveSampleRate=%u\n",
                  durationMs, totalBytesRead, recordingBytesWritten, recordingChunkCount, avgBytesPerChunk, effectiveSampleRate);

    // Upload flow: branch on what the mid-session identify attempt (if any)
    // found. Runs synchronously here, so it adds upload latency to the
    // LISTENING transition below.
    if (!identifyAttempted) {
      Serial.println("[UPLOAD] No identify attempt this session -- skipping conversation upload.");
    } else if (lastIdentifyMatch) {
      String unusedTranscript, unusedSummary;
      int httpCode = postConversationAudio(kSummarizeUrl, latestClosedRecordingFilename, lastIdentifyPatientId,
                                            lastIdentifyKnownPersonId, true, unusedTranscript, unusedSummary);
      if (httpCode >= 200 && httpCode < 300) {
        Serial.printf("[UPLOAD] summarize/ succeeded (HTTP %d) for known_person_id=%ld\n", httpCode, lastIdentifyKnownPersonId);
      } else {
        Serial.printf("[UPLOAD] summarize/ failed (HTTP %d) for known_person_id=%ld\n", httpCode, lastIdentifyKnownPersonId);
      }
    } else if (heldIdentifyImageBytes != nullptr && heldIdentifyImageLength > 0) {
      String transcript, summary;
      int transcribeCode = postConversationAudio(kTranscribeUrl, latestClosedRecordingFilename, lastIdentifyPatientId,
                                                   0, false, transcript, summary);
      if (transcribeCode >= 200 && transcribeCode < 300 && summary.length() > 0) {
        bool createOk = postCreateFromEncounter(heldIdentifyImageBytes, heldIdentifyImageLength, summary, lastIdentifyPatientId);
        Serial.printf("[UPLOAD] create-from-encounter %s\n", createOk ? "succeeded" : "failed");
      } else {
        Serial.printf("[UPLOAD] transcribe/ did not return a usable summary (HTTP %d) -- skipping create-from-encounter.\n", transcribeCode);
      }
    } else {
      // identifyAttempted but no image was ever captured this session (the
      // deinit/reinit capture itself failed) -- nothing to send to
      // create-from-encounter, and transcribing without a path to use the
      // result isn't useful, so skip both calls rather than let
      // create-from-encounter 400 on a missing "files" field.
      Serial.println("[UPLOAD] Identify attempted but no image was captured this session -- skipping transcribe/create-from-encounter.");
    }
  }

  // Free the held identify image regardless of which path above ran, or
  // whether recordingFile was even valid -- it must never carry over into
  // the next session.
  if (heldIdentifyImageBytes != nullptr) {
    free(heldIdentifyImageBytes);
    heldIdentifyImageBytes = nullptr;
    heldIdentifyImageLength = 0;
  }

  // Mic stays running -- LISTENING needs it continuously too.
  voiceActivityStartedAt = 0;
  setState(AppState::LISTENING);
}

// Serves the most recently *closed* recording (never the one currently
// being written, to avoid streaming a file mid-write with a still-placeholder
// header). Ground-truth check for the byte-count/duration instrumentation:
// fetch this and inspect it with a real WAV reader (e.g. Python's wave
// module) rather than trusting our own on-device accounting alone.
void handleLatestWav() {
  if (latestClosedRecordingFilename.length() == 0) {
    server.send(404, "text/plain", "No recording available yet.");
    return;
  }
  File file = SD.open(latestClosedRecordingFilename, FILE_READ);
  if (!file) {
    server.send(404, "text/plain", "Recording file could not be opened.");
    return;
  }
  server.streamFile(file, "audio/wav");
  file.close();
}

// TEMP diagnostic: triggers a few-seconds capture of the raw, unprocessed
// I2S stream (see rawCaptureActive's declaration comment). Fire this, then
// talk near the mic immediately -- the write happens inside drainMicChunk()
// on the very next loop() iterations.
void handleStartRawCapture() {
  if (!sdReady) {
    server.send(503, "text/plain", "SD not ready.");
    return;
  }
  if (rawCaptureFile) rawCaptureFile.close();
  rawCaptureFile = SD.open("/rawcap.bin", FILE_WRITE);
  if (!rawCaptureFile) {
    server.send(500, "text/plain", "Failed to open /rawcap.bin for writing.");
    return;
  }
  rawCaptureBytesRemaining = kRawCaptureBytesBudget;
  rawCaptureActive = true;
  server.send(200, "text/plain", "Raw capture started.");
}

// Serves the raw capture once finished (rawCaptureActive false again).
// Interpret as raw little-endian int32_t samples, interleaved
// Left,Right,Left,Right... -- no shift, no de-interleave, no gain applied.
void handleRawCaptureFile() {
  if (rawCaptureActive) {
    server.send(409, "text/plain", "Raw capture still in progress.");
    return;
  }
  File file = SD.open("/rawcap.bin", FILE_READ);
  if (!file) {
    server.send(404, "text/plain", "No raw capture available yet.");
    return;
  }
  server.streamFile(file, "application/octet-stream");
  file.close();
}

// TEMP diagnostic: durable, pollable view of the two setup()-time warm-up
// captures and the last mid-RECORDING identify attempt -- avoids needing a
// serial monitor to be attached at the exact right moment during boot.
void handleStatus() {
  // TEMP: livePeak -- for validating the INMP441 integration's kNoiseFloor
  // against real quiet/talk numbers over HTTP, avoiding a serial monitor
  // (whose disconnect hard-resets the board via RTS, wiping this exact
  // state). Mirrors recordingPeakSinceLastPrint, which printStatus() already
  // resets once/sec, so this reflects roughly the last ~1s window.
  String body = "livePeak: " + String(recordingPeakSinceLastPrint) + "\n" +
                "warmup1 (mic off): " + warmup1ResultText + "\n" +
                "warmup2 (mic on): " + warmup2ResultText + "\n" +
                "identifyAttempted: " + String(identifyAttempted ? "true" : "false") + "\n" +
                "lastIdentifyMatch: " + String(lastIdentifyMatch ? "true" : "false") + "\n" +
                "lastIdentifyName: " + lastIdentifyName + "\n" +
                "lastIdentifyRelationship: " + lastIdentifyRelationship + "\n" +
                "lastIdentifySummary: " + lastIdentifySummary + "\n" +
                "lastIdentifyKnownPersonId: " + String(lastIdentifyKnownPersonId) + "\n" +
                "lastIdentifyPatientId: " + String(lastIdentifyPatientId) + "\n" +
                "heldIdentifyImageLength: " + String((unsigned long)heldIdentifyImageLength) + "\n";
  server.send(200, "text/plain", body);
}

}  // namespace

void setup() {
  Serial.begin(115200);

  // Native USB CDC on this board: give the host time to finish
  // re-enumerating after reset/power-on, or early prints get lost.
  delay(3000);

  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  Serial.print("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }

  Serial.println();
  Serial.println("WiFi connected.");

  cameraReady = initCamera();
  if (!cameraReady) {
    Serial.println("Camera unavailable; capture loop will stay idle.");
  } else {
    warmup1ResultText = runWarmupCapture("#1 (mic off)");
  }

  sdReady = initSd();
  if (!sdReady) {
    Serial.println("SD card unavailable; recordings will not be saved to disk.");
  }

  micReady = initMic();
  if (!micReady) {
    Serial.println("Mic unavailable; voice-activity detection will stay idle.");
  } else if (cameraReady) {
    warmup2ResultText = runWarmupCapture("#2 (mic on)");
  }

  server.on("/latest.wav", HTTP_GET, handleLatestWav);
  server.on("/startrawcapture", HTTP_GET, handleStartRawCapture);
  server.on("/rawcapture.bin", HTTP_GET, handleRawCaptureFile);
  server.on("/status", HTTP_GET, handleStatus);
  server.begin();
  Serial.println("HTTP server started.");

  setState(AppState::LISTENING);
}

void loop() {
  static uint32_t lastPrint = 0;
  static uint32_t lastStatusPrint = 0;
  uint32_t iterationStartUs = micros();
  uint32_t now = millis();

  if (now - lastPrint >= kIpPrintIntervalMs) {
    lastPrint = now;
    Serial.print("IP address: ");
    Serial.println(WiFi.localIP());
  }

  server.handleClient();

  // No camera capture here -- that's a separate, later step. This loop is
  // purely: drain the mic continuously (both states need it), track the
  // rolling duty cycle, and transition LISTENING <-> RECORDING.
  if (!micReady) {
    recordLoopIterationDuration(iterationStartUs);
    return;
  }

  evictExpiredDutyCycleSamples(now);

  loopCallsSinceLastPrint++;
  drainMicChunk(now);

  float dutyCyclePercent = currentDutyCyclePercent();

  if (currentState == AppState::LISTENING) {
    if (dutyCyclePercent >= kVoiceActivityDutyCycleThreshold) {
      if (voiceActivityStartedAt == 0) voiceActivityStartedAt = now;
      if (now - voiceActivityStartedAt >= kVoiceActivityThresholdMs) {
        enterRecording();
      }
    } else {
      voiceActivityStartedAt = 0;
    }
  } else {  // AppState::RECORDING
    if (!identifyAttempted && cameraReady &&
        (now - recordingSessionStartedAtMs) >= kIdentifyDelayMsPlaceholder) {
      identifyAttempted = true;  // set before attempting -- never retry this session either way
      Serial.printf("[IDENTIFY] Firing mid-session capture at +%lums into recording\n",
                    (unsigned long)(now - recordingSessionStartedAtMs));
      // Deinit+reinit immediately before capturing, not a direct
      // esp_camera_fb_get() call -- confirmed necessary: mic is actively
      // running via I2S at this point (deep into RECORDING), the one
      // condition that reliably breaks a direct capture. I2S/mic and SD
      // are never touched by this.
      camera_fb_t *fb = captureFrameViaReinit();
      if (fb) {
        // Copy the JPEG out before returning the frame buffer / deiniting
        // the camera below -- fb won't survive until exitRecording(), but
        // the no-match path there needs these bytes for create-from-encounter.
        heldIdentifyImageBytes = psramFound() ? (uint8_t *)ps_malloc(fb->len) : (uint8_t *)malloc(fb->len);
        if (heldIdentifyImageBytes) {
          memcpy(heldIdentifyImageBytes, fb->buf, fb->len);
          heldIdentifyImageLength = fb->len;
        } else {
          Serial.println("[IDENTIFY] Failed to allocate buffer to hold captured image for later upload.");
          heldIdentifyImageLength = 0;
        }

        lastIdentifyMatch = identifyKnownPerson(fb, lastIdentifyName, lastIdentifyRelationship, lastIdentifySummary,
                                                 lastIdentifyKnownPersonId, lastIdentifyPatientId);
        esp_camera_fb_return(fb);
        Serial.printf("[IDENTIFY] result: match=%s name=%s relationship=%s last_summary=%s\n",
                      lastIdentifyMatch ? "true" : "false", lastIdentifyName.c_str(),
                      lastIdentifyRelationship.c_str(), lastIdentifySummary.c_str());
      } else {
        Serial.println("[IDENTIFY] capture failed (even after deinit/reinit) -- no identify attempt made this session.");
      }
      // Leave the camera dormant until actually needed again -- matches the
      // audio-first "camera only active when needed" design intent.
      esp_camera_deinit();
    }

    if (dutyCyclePercent <= kSilenceDutyCycleThreshold) {
      if (silenceStartedAt == 0) silenceStartedAt = now;
      if (now - silenceStartedAt >= kSilenceTimeoutMsPlaceholder) {
        exitRecording();
      }
    } else {
      silenceStartedAt = 0;
    }
  }

  if (now - lastStatusPrint >= kStatusPrintIntervalMs) {
    lastStatusPrint = now;
    printStatus(dutyCyclePercent);
  }

  recordLoopIterationDuration(iterationStartUs);
}
