import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLanguage extends ChangeNotifier {
  static const String _storageKey = 'app_selected_language';
  static const List<String> supportedLanguages = ['English', 'Kannada', 'Telugu', 'Tamil', 'Hindi'];

  static final AppLanguage _instance = AppLanguage._internal();

  factory AppLanguage() => _instance;

  AppLanguage._internal();

  String _language = 'English';

  String get language => _language;

  Locale get locale => _localeFor(_language);

  static List<Locale> get supportedLocales => const [
    Locale('en'),
    Locale('kn'),
    Locale('te'),
    Locale('ta'),
    Locale('hi'),
  ];

  static Locale _localeFor(String language) {
    switch (language) {
      case 'Kannada':
        return const Locale('kn');
      case 'Telugu':
        return const Locale('te');
      case 'Tamil':
        return const Locale('ta');
      case 'Hindi':
        return const Locale('hi');
      case 'English':
      default:
        return const Locale('en');
    }
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_storageKey) ?? 'English';
    if (supportedLanguages.contains(stored)) {
      _language = stored;
    } else {
      _language = 'English';
    }
    notifyListeners();
  }

  Future<void> setLanguage(String language) async {
    final next = supportedLanguages.contains(language) ? language : 'English';
    if (_language == next) return;
    _language = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, next);
    notifyListeners();
  }

  String translate(String key) {
    final map = _translations[_language] ?? _translations['English'] ?? {};
    return map[key] ?? _translations['English']?[key] ?? key;
  }

  static final Map<String, Map<String, String>> _translations = {
    'English': {
      'checking_whos_here': "Checking who's here...",
      'scanning_known_patient': 'Scanning for a known patient...',
      'no_face_detected': 'No face detected',
      'no_matching_patient_found': 'No matching patient found',
      'ready_to_scan': 'Ready to scan',
      'people_i_ve_talked_to': 'People I’ve talked to',
      'no_recent_memories_yet': 'No recent memories yet.',
      'scan_using_camera_icon': 'Scan using camera icon',
      'ask_caregiver_to_save_profile': 'Ask caregiver to save patient profile first',
      'unknown_person_detected': 'Unknown person detected',
      'patient_not_enrolled': 'Patient not enrolled yet. Caregiver must save profile before scan.',
      'patient_mode': 'Patient mode',
      'recent_memories': 'Recent memories',
      'conversation_capture_active': 'Conversation capture is active.',
      'glasses_recording': 'Your glasses are recording this conversation.',
      'last_conversation': 'Last conversation',
      'no_previous_conversation_found': 'No previous conversation found.',
      'start_conversation': 'Start Conversation',
      'stop_recording': 'Stop recording',
      'saving': 'Saving...',
      'capturing_conversation': 'Capturing conversation...',
      'waiting_for_speech': 'Waiting for speech...',
      'listening': 'Listening...',
      'language': 'Language',
      'recognized': 'Recognized',
      'exit_patient_mode_question': 'Exit patient mode?',
      'exit_patient_mode_message': 'This closes the patient screen and returns to caregiver sign-in.',
      'cancel': 'Cancel',
      'exit': 'Exit',
      'back_to_home': 'Back to Home',
      'try_again': 'Please try again.',
      'speaking_last_summary': 'Speaking last summary...',
      'ready_to_capture': 'Ready to capture your conversation.',
      'starting_recording': 'Starting recording...',
      'recording_not_started': 'Recording not started.',
      'microphone_required': 'Microphone permission is required to record your conversation.',
      'no_speech_detected': 'No speech detected for 5 seconds. Stopping capture...',
      'conversation_saved_success': 'Conversation saved successfully. Returning home...',
      'conversation_save_failed': 'Failed to save conversation. You can try again from home.',
      'people_talked_to': 'People I’ve talked to',
      'session_expired': 'Your session expired. Please sign in again.',
    },
    'Kannada': {
      'checking_whos_here': 'ಯಾರು ಇಲ್ಲಿದ್ದಾರೆ ಎಂದು ಪರಿಶೀಲಿಸಲಾಗುತ್ತಿದೆ...',
      'scanning_known_patient': 'ಗೊತ್ತಿದ ರೋಗಿಯನ್ನು ಸ್ಕ್ಯಾನ್ ಮಾಡಲಾಗುತ್ತಿದೆ...',
      'no_face_detected': 'ಮುಖ ಕಂಡುಬಂದಿಲ್ಲ',
      'no_matching_patient_found': 'ಹೊಂದಾಣಿಕೆಯ ರೋಗಿ ಕಂಡುಬಂದಿಲ್ಲ',
      'ready_to_scan': 'ಸ್ಕ್ಯಾನ್ ಮಾಡಲು ಸಿದ್ಧವಾಗಿದೆ',
      'people_i_ve_talked_to': 'ನಾನು ಮಾತನಾಡಿದ ಜನರು',
      'no_recent_memories_yet': 'ಇನ್ನೂ ಯಾವುದೇ ಇತ್ತೀಚಿನ ನೆನಪುಗಳಿಲ್ಲ.',
      'scan_using_camera_icon': 'ಕ್ಯಾಮೆರಾ ಐಕಾನ್ ಬಳಸಿ ಸ್ಕ್ಯಾನ್ ಮಾಡಿ',
      'ask_caregiver_to_save_profile': 'ಪೇಷಕರು ರೋಗಿಯ ಪ್ರೊಫೈಲ್ ಅನ್ನು ಸೇವ್ ಮಾಡಬೇಕು',
      'unknown_person_detected': 'ಅಪರಿಚಿತ ವ್ಯಕ್ತಿ ಪತ್ತೆಯಾಗಿದೆ',
      'patient_not_enrolled': 'ರೋಗಿಯನ್ನು ನೋಂದಾಯಿಸಿಲ್ಲ. ಸ್ಕ್ಯಾನ್ ಮಾಡುವ ಮೊದಲು ಕೇರ್‌ಗಾರರು ಪ್ರೊಫೈಲ್ ಸೇವ್ ಮಾಡಬೇಕು.',
      'patient_mode': 'ರೋಗಿ ಮೋಡ್',
      'recent_memories': 'ಇತ್ತೀಚಿನ ನೆನಪುಗಳು',
      'conversation_capture_active': 'ಮಾತುಕಥೆ ಸೆರೆಹಿಡಿಯುವಿಕೆ ಸಕ್ರಿಯವಾಗಿದೆ.',
      'glasses_recording': 'ನಿಮ್ಮ ಕಣ್ಣಡಿಯಲ್ಲಿ ಈ ಸಂಭಾಷಣೆಯನ್ನು ರೆಕಾರ್ಡ್ ಮಾಡಲಾಗುತ್ತಿದೆ.',
      'last_conversation': 'ಕೊನೆಯ ಸಂಭಾಷಣೆ',
      'no_previous_conversation_found': 'ಹಿಂದಿನ ಸಂಭಾಷಣೆ ಕಂಡುಬಂದಿಲ್ಲ.',
      'start_conversation': 'ಸಂಭಾಷಣೆ शुरूಮಾಡಿ',
      'stop_recording': 'ರೆಕಾರ್ಡಿಂಗ್ ನಿಲ್ಲಿಸಿ',
      'saving': 'ಸೇವ್ ಮಾಡಲಾಗುತ್ತಿದೆ...',
      'capturing_conversation': 'ಸಂಭಾಷಣೆಯನ್ನು ಸೆರೆಹಿಡಿಯಲಾಗುತ್ತಿದೆ...',
      'waiting_for_speech': 'ಮಾತು ನಿರೀಕ್ಷಿಸಲಾಗುತ್ತಿದೆ...',
      'listening': 'ಕೇಳಲಾಗುತ್ತಿದೆ...',
      'language': 'ಭಾಷೆ',
      'recognized': 'ಗುರುತಿಸಲಾಗಿದೆ',
      'exit_patient_mode_question': 'ರೋಗಿ ಮೋಡ್‌ನಿಂದ ನಿರ್ಗಮಿಸುವುದೇ?',
      'exit_patient_mode_message': 'ಇದು ರೋಗಿ ಪರದೆಯನ್ನು ಮುಚ್ಚಿ ಕೇರ್‌ಗಾರರ ಸೈನ್-ಇನ್‌ಗೆ തിരികೆ ತರುತ್ತದೆ.',
      'cancel': 'ರದ್ದುಮಾಡು',
      'exit': 'ನಿರ್ಗಮಿಸಿ',
      'back_to_home': 'ಮನೆಗೆ ಹಿಂತಿರುಗಿ',
      'try_again': 'ದಯವಿಟ್ಟು ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.',
      'speaking_last_summary': 'ಕೊನೆಯ ಸಾರಾಂಶವನ್ನು ಹೇಳಲಾಗುತ್ತಿದೆ...',
      'ready_to_capture': 'ನಿಮ್ಮ ಸಂಭಾಷಣೆಯನ್ನು ಸೆರೆಹಿಡಿಯಲು ಸಿದ್ಧವಾಗಿದೆ.',
      'starting_recording': 'ರೆಕಾರ್ಡಿಂಗ್ ಪ್ರಾರಂಭಿಸಲಾಗುತ್ತಿದೆ...',
      'recording_not_started': 'ರೆಕಾರ್ಡಿಂಗ್ ಪ್ರಾರಂಭವಾಗಲಿಲ್ಲ.',
      'microphone_required': 'ನಿಮ್ಮ ಸಂಭಾಷಣೆಯನ್ನು ರೆಕಾರ್ಡ್ ಮಾಡಲು ಮೈಕ್ರೋಫೋನ್ ಅನುಮತಿ ಅಗತ್ಯವಿದೆ.',
      'no_speech_detected': '5 ಸೆಕೆಂಡುಗಳಲ್ಲಿ ಮಾತನಾಡು ಕಂಡುಬಂದಿಲ್ಲ. ಸೆರೆಹಿಡಿಯುವುದನ್ನು ನಿಲ್ಲಿಸಲಾಗುತ್ತಿದೆ...',
      'conversation_saved_success': 'ಸಂಭಾಷಣೆ 저장되었습니다. ಮನೆಗೆ ಮರಳಲಾಗುತ್ತಿದೆ...',
      'conversation_save_failed': 'ಸಂಭಾಷಣೆಯನ್ನು ಉಳಿಸಲು ವಿಫಲವಾಯಿತು. ನೀವು المنزلದಿಂದ ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಬಹುದು.',
      'people_talked_to': 'ನಾನು ಮಾತನಾಡಿದ ಜನರು',
      'session_expired': 'ನಿಮ್ಮ ಸೀಷನ್ ಮುಗಿದಿದೆ. ದಯವಿಟ್ಟು ಮತ್ತೆ ಸೈನ್ ಇನ್ ಮಾಡಿ.',
    },
    'Telugu': {
      'checking_whos_here': 'ఎవరు ఇక్కడ ఉన్నారు అని పరిశీలిస్తున్నాం...',
      'scanning_known_patient': 'గుర్తించబడిన పేషెంట్ను స్కాన్ చేస్తున్నాం...',
      'no_face_detected': 'ముఖం కనబడలేదు',
      'no_matching_patient_found': 'పోలిక ఉన్న పేషెంట్ కనబడలేదు',
      'ready_to_scan': 'స్కాన్‌కి సిద్ధంగా ఉంది',
      'people_i_ve_talked_to': 'నేను మాట్లాడిన వ్యక్తులు',
      'no_recent_memories_yet': 'ఇప్పటివరకు ఇటీవలి జ్ఞాపకాలు లేవు.',
      'scan_using_camera_icon': 'కెమెరా ఐకాన్‌తో స్కాన్ చేయండి',
      'ask_caregiver_to_save_profile': 'పేషెంట్ ప్రొఫైల్ సేవ్ చేయడానికి కేర్‌గివర్‌కు చెప్పండి',
      'unknown_person_detected': 'అజ్ఞాత వ్యక్తి కనబడినాడు',
      'patient_not_enrolled': 'పేషెంట్ నమోదు చేయబడలేదు. స్కాన్‌కి ముందు కేర్‌గివర్ ప్రొఫైల్ సేవ్ చేయాలి.',
      'patient_mode': 'పేషెంట్ మోడ్',
      'recent_memories': 'ఇటీవలి జ్ఞాపకాలు',
      'conversation_capture_active': 'మాట్లాడటం రికార్డ్ అవుతోంది.',
      'glasses_recording': 'మీ అద్దాలు ఈ సంభాషణను రికార్డ్ చేస్తున్నాయి.',
      'last_conversation': 'చివరి సంభాషణ',
      'no_previous_conversation_found': 'మునుపటి సంభాషణ కనబడలేదు.',
      'start_conversation': 'సంభాషణ ప్రారంభించండి',
      'stop_recording': 'రికార్డింగ్ ఆపండి',
      'saving': 'సేవ్ చేస్తున్నాం...',
      'capturing_conversation': 'సంభాషణను రికార్డ్ చేస్తున్నాం...',
      'waiting_for_speech': 'మాట కోసం వేచి ఉన్నాం...',
      'listening': 'వినుగోంటున్నాం...',
      'language': 'భాష',
      'recognized': 'గుర్తించబడింది',
      'exit_patient_mode_question': 'పేషెంట్ మోడ్ నుండి వెళ్లాలా?',
      'exit_patient_mode_message': 'ఇది పేషెంట్ స్క్రీన్‌ను మూసివేసి కేర్‌గివర్ సైన్-ఇన్‌కు తిరిగి తీసుకెళుతుంది.',
      'cancel': 'రద్దు',
      'exit': 'నిష్క్రమించండి',
      'back_to_home': 'ఇంటికి తిరిగి వెళ్లండి',
      'try_again': 'దయచేసి మళ్లీ ప్రయత్నించండి.',
      'speaking_last_summary': 'చివరి సారాంశాన్ని మాట్లాడుతున్నాం...',
      'ready_to_capture': 'మీ సంభాషణను రికార్డ్ చేయడానికి సిద్దంగా ఉంది.',
      'starting_recording': 'రికార్డింగ్ ప్రారంభమవుతోంది...',
      'recording_not_started': 'రికార్డింగ్ ప్రారంభం కాలేదు.',
      'microphone_required': 'మీ సంభాషణను రికార్డ్ చేయడానికి మైక్రోఫోన్ అనుమతి అవసరం.',
      'no_speech_detected': '5 సెకన్లలో మాట కనబడలేదు. రికార్డింగ్ ఆపబడుతోంది...',
      'conversation_saved_success': 'సంభాషణ సేవ్ అయింది. ఇంటికి తిరుగుతోంది...',
      'conversation_save_failed': 'సంభాషణను సేవ్ చేయడంలో విఫలమైంది. మీరు ఇంటి నుండి మళ్లీ ప్రయత్నించవచ్చు.',
      'people_talked_to': 'నేను మాట్లాడిన వ్యక్తులు',
      'session_expired': 'మీ సెషన్ గడువు ముగిసింది. దయచేసి మళ్లీ సైన్ ఇన్ చేయండి.',
    },
    'Tamil': {
      'checking_whos_here': 'இங்கு யார் இருக்கிறார்கள் என்று சரிபார்க்கிறோம்...',
      'scanning_known_patient': 'அறியப்பட்ட நோயாளியை ஸ்கேன் செய்கிறோம்...',
      'no_face_detected': 'முகம் கண்டறியப்படவில்லை',
      'no_matching_patient_found': 'பொருந்தும் நோயாளர் இல்லை',
      'ready_to_scan': 'ஸ்கேன் செய்ய தயாராக உள்ளது',
      'people_i_ve_talked_to': 'நான் பேசியவர்கள்',
      'no_recent_memories_yet': 'இதுவரை சமீபத்திய நினைவுகள் இல்லை.',
      'scan_using_camera_icon': 'கேமரா ஐகானைப் பயன்படுத்தி ஸ்கேன் செய்யுங்கள்',
      'ask_caregiver_to_save_profile': 'நோயாளியின் சுயவிவரத்தை சேமிக்க பராமரிப்பாளரை கேளுங்கள்',
      'unknown_person_detected': 'அறிமுகமில்லாத நபர் கண்டறியப்பட்டார்',
      'patient_not_enrolled': 'நோயாளர் பதிவு செய்யப்படவில்லை. ஸ்கேன் செய்வதற்கு முன் பராமரிப்பாளர் சுயவிவரத்தை சேமிக்க வேண்டும்.',
      'patient_mode': 'நோயாளர் முறை',
      'recent_memories': 'சமீபத்திய நினைவுகள்',
      'conversation_capture_active': 'உரையாடல் பதிவு செயலிலுள்ளது.',
      'glasses_recording': 'உங்கள் கண்ணாடிகள் இந்த உரையாடலை பதிவு செய்கின்றன.',
      'last_conversation': 'கடைசி உரையாடல்',
      'no_previous_conversation_found': 'முந்தைய உரையாடல் இல்லை.',
      'start_conversation': 'உரையாடலைத் தொடங்குங்கள்',
      'stop_recording': 'பதிவை நிறுத்து',
      'saving': 'சேமிக்கப்படுகிறது...',
      'capturing_conversation': 'உரையாடலை பதிவு செய்கின்றோம்...',
      'waiting_for_speech': 'பேச்சுக்காக காத்திருக்கிறோம்...',
      'listening': 'கேட்கிறோம்...',
      'language': 'மொழி',
      'recognized': 'அடையாளம் காணப்பட்டது',
      'exit_patient_mode_question': 'நோயாளர் முறையிலிருந்து வெளியேற வேண்டுமா?',
      'exit_patient_mode_message': 'இது நோயாளர் திரையை மூடி பராமரிப்பாளர் சைன்-இன் பக்கத்திற்குத் திருப்பி விடும்.',
      'cancel': 'ரத்து',
      'exit': 'வெளியேறு',
      'back_to_home': 'வீட்டிற்கு திரும்பு',
      'try_again': 'தயவுசெய்து மீண்டும் முயற்சிக்கவும்.',
      'speaking_last_summary': 'கடைசி சுருக்கத்தை பேசுகிறோம்...',
      'ready_to_capture': 'உங்கள் உரையாடலைப் பதிவுசெய்ய தயாராக உள்ளது.',
      'starting_recording': 'பதிவு தொடங்குகிறது...',
      'recording_not_started': 'பதிவு தொடங்கவில்லை.',
      'microphone_required': 'உங்கள் உரையாடலைப் பதிவுசெய்ய மைக்ரோஃபோன் அனுமதி தேவை.',
      'no_speech_detected': '5 விநாடிகளில் பேச்சு கண்டறியப்படவில்லை. பதிவு நிறுத்தப்படுகிறது...',
      'conversation_saved_success': 'உரையாடல் சேமிக்கப்பட்டது. வீட்டிற்கு திரும்புகிறது...',
      'conversation_save_failed': 'உரையாடலைச் சேமிக்க முடியவில்லை. வீட்டிலிருந்து மீண்டும் முயற்சி செய்யலாம்.',
      'people_talked_to': 'நான் பேசிக் கொண்டவர்கள்',
      'session_expired': 'உங்கள் அமர்வு முடிந்துவிட்டது. மீண்டும் சைன் இன் செய்யவும்.',
    },
    'Hindi': {
      'checking_whos_here': 'यहाँ कौन है देख रहे हैं...',
      'scanning_known_patient': 'मालूम रोगी की पहचान की जा रही है...',
      'no_face_detected': 'चेहरा नहीं मिला',
      'no_matching_patient_found': 'मिलान करने वाला रोगी नहीं मिला',
      'ready_to_scan': 'स्कैन के लिए तैयार',
      'people_i_ve_talked_to': 'मैंने जिनसे बात की',
      'no_recent_memories_yet': 'अभी तक कोई हाल की यादें नहीं हैं।',
      'scan_using_camera_icon': 'कैमरा आइकन से स्कैन करें',
      'ask_caregiver_to_save_profile': 'रोगी का प्रोफ़ाइल सेव करने के लिए देखभालकर्ता से कहें',
      'unknown_person_detected': 'अजनबी व्यक्ति पाया गया',
      'patient_not_enrolled': 'रोगी पंजीकृत नहीं है। स्कैन से पहले देखभालकर्ता प्रोफ़ाइल सेव करेगा।',
      'patient_mode': 'रोगी मोड',
      'recent_memories': 'हाल की यादें',
      'conversation_capture_active': 'बातचीत रिकॉर्डिंग सक्रिय है।',
      'glasses_recording': 'आपके चश्मे यह बातचीत रिकॉर्ड कर रहे हैं।',
      'last_conversation': 'अंतिम बातचीत',
      'no_previous_conversation_found': 'पिछली बातचीत नहीं मिली।',
      'start_conversation': 'बातचीत शुरू करें',
      'stop_recording': 'रिकॉर्डिंग रोकें',
      'saving': 'सेव हो रहा है...',
      'capturing_conversation': 'बातचीत रिकॉर्ड की जा रही है...',
      'waiting_for_speech': 'भाषण की प्रतीक्षा...',
      'listening': 'सुन रहे हैं...',
      'language': 'भाषा',
      'recognized': 'पहचाना गया',
      'exit_patient_mode_question': 'रोगी मोड से बाहर निकलें?',
      'exit_patient_mode_message': 'यह रोगी स्क्रीन बंद कर देगा और देखभालकर्ता साइन-इन पर लौटाएगा।',
      'cancel': 'रद्द करें',
      'exit': 'बाहर निकलें',
      'back_to_home': 'होम पर वापस जाएँ',
      'try_again': 'कृपया फिर से प्रयास करें।',
      'speaking_last_summary': 'अंतिम सारांश पढ़ा जा रहा है...',
      'ready_to_capture': 'आपकी बातचीत रिकॉर्ड करने के लिए तैयार है।',
      'starting_recording': 'रिकॉर्डिंग शुरू हो रही है...',
      'recording_not_started': 'रिकॉर्डिंग शुरू नहीं हुई।',
      'microphone_required': 'आपकी बातचीत रिकॉर्ड करने के लिए माइक्रोफोन अनुमति आवश्यक है।',
      'no_speech_detected': '5 सेकंड में बोल नहीं मिला। रिकॉर्डिंग रोक रही है...',
      'conversation_saved_success': 'बातचीत सेव हो गई। होम पर लौट रहे हैं...',
      'conversation_save_failed': 'बातचीत सेव नहीं हुई। आप घर से फिर से कोशिश कर सकते हैं।',
      'people_talked_to': 'मैंने जिनसे बात की',
      'session_expired': 'आपका सत्र समाप्त हो गया है। कृपया फिर से साइन इन करें।',
    },
  };
}
