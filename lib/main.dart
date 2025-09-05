import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:zego_uikit_prebuilt_video_conference/zego_uikit_prebuilt_video_conference.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize logging
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    debugPrint('${record.level.name}: ${record.time}: ${record.message}');
  });

  // Load environment variables
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    Logger('Main').severe('Failed to load .env file: $e');
  }

  runApp(const MyApp());
}

class ConfigService {
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;
  ConfigService._internal();

  int? get zegoAppId => int.tryParse(dotenv.get('ZEGO_APP_ID', fallback: ''));
  String get zegoAppSign => dotenv.get('ZEGO_APP_SIGN', fallback: '');

  bool validate() {
    if (zegoAppId == null || zegoAppSign.isEmpty) {
      Logger('ConfigService').severe('Invalid ZEGO configuration');
      return false;
    }
    return true;
  }
}

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  final _secureStorage = const FlutterSecureStorage();
  final _prefs = SharedPreferences.getInstance();

  Future<void> saveUserName(String userName) async {
    try {
      await _secureStorage.write(key: 'userName', value: userName);
    } catch (e) {
      Logger('StorageService').warning('Failed to save username: $e');
    }
  }

  Future<String?> getUserName() async {
    try {
      return await _secureStorage.read(key: 'userName');
    } catch (e) {
      Logger('StorageService').warning('Failed to read username: $e');
      return null;
    }
  }

  Future<void> saveRecentMeetings(List<String> meetings) async {
    try {
      final prefs = await _prefs;
      await prefs.setStringList('recentMeetings', meetings);
    } catch (e) {
      Logger('StorageService').warning('Failed to save recent meetings: $e');
    }
  }

  Future<List<String>> getRecentMeetings() async {
    try {
      final prefs = await _prefs;
      return prefs.getStringList('recentMeetings') ?? [];
    } catch (e) {
      Logger('StorageService').warning('Failed to read recent meetings: $e');
      return [];
    }
  }

  Future<void> removeRecentMeeting(String meetingId) async {
    try {
      final prefs = await _prefs;
      final meetings = prefs.getStringList('recentMeetings') ?? [];
      meetings.remove(meetingId);
      await prefs.setStringList('recentMeetings', meetings);
    } catch (e) {
      Logger('StorageService').warning('Failed to remove recent meeting: $e');
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ConnectMeet Pro',
      theme: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4E6DFF),
          primary: const Color(0xFF4E6DFF),
          secondary: const Color(0xFFFF6B6B),
          background: const Color(0xFFF8FAFF),
          surface: Colors.white,
          onSurface: const Color(0xFF2D2D2D),
        ),
        textTheme: GoogleFonts.poppinsTextTheme().apply(
          bodyColor: const Color(0xFF2D2D2D),
          displayColor: const Color(0xFF2D2D2D),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4E6DFF),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            elevation: 2,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF4E6DFF), width: 2),
          ),
          labelStyle: GoogleFonts.poppins(
            color: const Color(0xFF7B7B7B),
            fontSize: 14,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          prefixIconColor: const Color(0xFF7B7B7B),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 1,
          titleTextStyle: GoogleFonts.poppins(
            color: const Color(0xFF2D2D2D),
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          iconTheme: const IconThemeData(color: Color(0xFF4E6DFF)),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  final _logger = Logger('HomePage');
  final String userId = (Random().nextInt(900000) + 100000).toString();
  final String randomConferenceId = _generateConferenceId();
  final conferenceIdController = TextEditingController();
  final userNameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _isLoading = true;
  List<String> _recentMeetings = [];
  final _storageService = StorageService();
  final _configService = ConfigService();

  static String _generateConferenceId() {
    final random = Random();
    return (random.nextInt(1000000000) * 10 + random.nextInt(10))
        .toString()
        .padLeft(10, '0');
  }

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );

    await _loadUserData();
    _animationController.forward();
  }

  Future<void> _loadUserData() async {
    try {
      final userName = await _storageService.getUserName();
      final recentMeetings = await _storageService.getRecentMeetings();

      setState(() {
        userNameController.text = userName ?? '';
        _recentMeetings = recentMeetings;
        _isLoading = false;
      });
    } catch (e) {
      _logger.warning('Error loading user data: $e');
      _showSnackBar(context, 'Failed to load user data');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveUserData() async {
    try {
      await _storageService.saveUserName(userNameController.text.trim());
    } catch (e) {
      _logger.warning('Error saving user data: $e');
      _showSnackBar(context, 'Failed to save user data');
    }
  }

  void _addToRecentMeetings(String meetingId) async {
    final formattedId = _formatMeetingId(meetingId);
    if (!_recentMeetings.contains(formattedId)) {
      setState(() {
        if (_recentMeetings.length >= 5) {
          _recentMeetings.removeLast();
        }
        _recentMeetings.insert(0, formattedId);
      });
      await _storageService.saveRecentMeetings(_recentMeetings);
    }
  }

  void _removeRecentMeeting(String meetingId) async {
    setState(() {
      _recentMeetings.remove(meetingId);
    });
    await _storageService.removeRecentMeeting(meetingId);
  }

  String _formatMeetingId(String id) {
    if (id.length != 10) return id;
    return '${id.substring(0, 3)}-${id.substring(3, 6)}-${id.substring(6)}';
  }

  String _unformatMeetingId(String formattedId) {
    return formattedId.replaceAll('-', '');
  }

  @override
  void dispose() {
    _animationController.dispose();
    conferenceIdController.dispose();
    userNameController.dispose();
    super.dispose();
  }

  void _showSnackBar(
    BuildContext context,
    String message, {
    bool isError = true,
    String? deletedMeetingId,
    VoidCallback? onUndo,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.poppins(color: Colors.white),
          semanticsLabel: message,
        ),
        backgroundColor: isError
            ? const Color(0xFFFF6B6B)
            : const Color(0xFF4E6DFF),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        action: onUndo != null
            ? SnackBarAction(
                label: 'Undo',
                textColor: Colors.white,
                onPressed: onUndo,
              )
            : SnackBarAction(
                label: 'Dismiss',
                textColor: Colors.white,
                onPressed: () =>
                    ScaffoldMessenger.of(context).hideCurrentSnackBar(),
              ),
      ),
    );
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text))
        .then((_) {
          _showSnackBar(
            context,
            'Meeting ID copied to clipboard',
            isError: false,
          );
        })
        .catchError((e) {
          _logger.warning('Failed to copy to clipboard: $e');
          _showSnackBar(context, 'Failed to copy Meeting ID');
        });
  }

  void _showMeetingInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Meeting Information',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            semanticsLabel: 'Meeting Information',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Meeting ID: ${_formatMeetingId(randomConferenceId)}',
                style: GoogleFonts.poppins(fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Share this ID with others to join your meeting',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: GoogleFonts.poppins(color: Colors.grey.shade600),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                _copyToClipboard(context, randomConferenceId);
                Navigator.pop(context);
              },
              child: const Text('Copy ID'),
            ),
          ],
        );
      },
    );
  }

  void _jumpToMeetingPage(
    BuildContext context, {
    required String conferenceId,
  }) {
    final unformattedId = _unformatMeetingId(conferenceId);

    if (unformattedId.isEmpty || unformattedId.length != 10) {
      _showSnackBar(context, 'Please enter a valid 10-digit Meeting ID');
      return;
    }

    if (userNameController.text.trim().isEmpty) {
      _showSnackBar(context, 'Please enter your name');
      return;
    }

    if (!_configService.validate()) {
      _showSnackBar(context, 'Invalid configuration. Please contact support.');
      return;
    }

    _saveUserData();
    _addToRecentMeetings(unformattedId);

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            VideoConferencePage(
              conferenceID: unformattedId,
              userID: userId,
              userName: userNameController.text.trim(),
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeInOutCubic;
          var tween = Tween(
            begin: begin,
            end: end,
          ).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: FadeTransition(opacity: animation, child: child),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
                semanticsLabel: 'Loading',
              ),
              const SizedBox(height: 20),
              Text(
                'Loading...',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        title: Text(
          'ConnectMeet Pro',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
          semanticsLabel: 'ConnectMeet Pro',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About ConnectMeet Pro',
            onPressed: () {
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    title: Text(
                      'About ConnectMeet Pro',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                    ),
                    content: Text(
                      'A professional video conferencing solution with crystal clear audio and video quality. Connect with your team, clients, and partners seamlessly.',
                      style: GoogleFonts.poppins(),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          'Close',
                          style: GoogleFonts.poppins(
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: SlideTransition(
            position: _slideAnimation,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Join a Meeting',
                              style: textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: colorScheme.onSurface,
                              ),
                              semanticsLabel: 'Join a Meeting',
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: userNameController,
                              decoration: const InputDecoration(
                                labelText: 'Your Name',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                              textCapitalization: TextCapitalization.words,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter your name';
                                }
                                if (value.trim().length < 2) {
                                  return 'Name must be at least 2 characters';
                                }
                                if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(value)) {
                                  return 'Name can only contain letters and spaces';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: conferenceIdController,
                              maxLength: 12,
                              keyboardType: TextInputType.number,
                              inputFormatters: [_MeetingIdInputFormatter()],
                              style: GoogleFonts.poppins(
                                color: colorScheme.onSurface,
                                fontSize: 16,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Meeting ID',
                                prefixIcon: Icon(Icons.groups_rounded),
                                counterText: "",
                                hintText: '123-456-7890',
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter a Meeting ID';
                                }
                                final cleanValue = _unformatMeetingId(value);
                                if (cleanValue.length != 10 ||
                                    int.tryParse(cleanValue) == null) {
                                  return 'Meeting ID must be a 10-digit number';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.login_rounded, size: 20),
                                label: const Text('Join Meeting'),
                                onPressed: () {
                                  if (_formKey.currentState!.validate()) {
                                    _jumpToMeetingPage(
                                      context,
                                      conferenceId: conferenceIdController.text,
                                    );
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Start a New Meeting',
                            style: textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onSurface,
                            ),
                            semanticsLabel: 'Start a New Meeting',
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Create an instant meeting or schedule for later',
                            style: GoogleFonts.poppins(
                              color: colorScheme.onSurface.withOpacity(0.7),
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: const Icon(
                                Icons.video_call_rounded,
                                size: 20,
                              ),
                              label: const Text('Instant Meeting'),
                              onPressed: () {
                                if (userNameController.text.trim().isEmpty) {
                                  _showSnackBar(
                                    context,
                                    'Please enter your name',
                                  );
                                  return;
                                }
                                _showMeetingInfoDialog(context);
                                _jumpToMeetingPage(
                                  context,
                                  conferenceId: randomConferenceId,
                                );
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                side: BorderSide(color: colorScheme.primary),
                                foregroundColor: colorScheme.primary,
                                textStyle: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton.icon(
                              icon: const Icon(Icons.schedule, size: 20),
                              label: const Text('Schedule Meeting'),
                              onPressed: () {
                                _showSnackBar(
                                  context,
                                  'Scheduling feature coming soon!',
                                  isError: false,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_recentMeetings.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Recent Meetings',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                      semanticsLabel: 'Recent Meetings',
                    ),
                    const SizedBox(height: 12),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _recentMeetings.length,
                      itemBuilder: (context, index) {
                        final meetingId = _recentMeetings[index];
                        return Dismissible(
                          key: Key(meetingId),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: Colors.red,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 16),
                            child: const Icon(
                              Icons.delete,
                              color: Colors.white,
                            ),
                          ),
                          onDismissed: (direction) {
                            final removedMeetingId = meetingId;
                            _removeRecentMeeting(removedMeetingId);
                            _showSnackBar(
                              context,
                              'Meeting ID $removedMeetingId deleted',
                              isError: false,
                              deletedMeetingId: removedMeetingId,
                              onUndo: () {
                                setState(() {
                                  _recentMeetings.insert(
                                    index,
                                    removedMeetingId,
                                  );
                                });
                                _storageService.saveRecentMeetings(
                                  _recentMeetings,
                                );
                              },
                            );
                          },
                          confirmDismiss: (direction) async {
                            return await showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                title: Text(
                                  'Delete Meeting',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  semanticsLabel: 'Delete Meeting',
                                ),
                                content: Text(
                                  'Are you sure you want to delete Meeting ID $meetingId?',
                                  style: GoogleFonts.poppins(),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: Text(
                                      'Cancel',
                                      style: GoogleFonts.poppins(
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ),
                                  ElevatedButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                          },
                          child: Card(
                            child: ListTile(
                              leading: const Icon(
                                Icons.history,
                                color: Color(0xFF4E6DFF),
                              ),
                              title: Text(
                                'Meeting ID: $meetingId',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w500,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              subtitle: Text(
                                'Tap to join',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: colorScheme.onSurface.withOpacity(0.6),
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.content_copy, size: 18),
                                onPressed: () {
                                  _copyToClipboard(context, meetingId);
                                },
                              ),
                              onTap: () {
                                conferenceIdController.text = meetingId;
                                if (userNameController.text.trim().isNotEmpty) {
                                  _jumpToMeetingPage(
                                    context,
                                    conferenceId: meetingId,
                                  );
                                } else {
                                  _showSnackBar(
                                    context,
                                    'Please enter your name',
                                  );
                                }
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class VideoConferencePage extends StatelessWidget {
  final String conferenceID;
  final String userID;
  final String userName;

  const VideoConferencePage({
    super.key,
    required this.conferenceID,
    required this.userID,
    required this.userName,
  });

  @override
  Widget build(BuildContext context) {
    final configService = ConfigService();
    final logger = Logger('VideoConferencePage');

    if (!configService.validate()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showErrorDialog(context);
      });
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
                semanticsLabel: 'Initializing',
              ),
              const SizedBox(height: 20),
              Text(
                'Initializing...',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: ZegoUIKitPrebuiltVideoConference(
        appID: configService.zegoAppId!,
        appSign: configService.zegoAppSign,
        userID: userID,
        userName: userName,
        conferenceID: conferenceID,
        config: ZegoUIKitPrebuiltVideoConferenceConfig(
          turnOnCameraWhenJoining: true,
          turnOnMicrophoneWhenJoining: true,
          useSpeakerWhenJoining: true,
          avatarBuilder:
              (
                BuildContext context,
                Size size,
                ZegoUIKitUser? user,
                Map extraInfo,
              ) {
                String avatarText = 'U';
                if (user != null) {
                  final String name = user.name.isNotEmpty
                      ? user.name
                      : 'User ${user.id}';
                  if (name.isNotEmpty) {
                    avatarText = name.substring(0, 1).toUpperCase();
                  }
                }

                return Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      avatarText,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: size.height / 2,
                        fontWeight: FontWeight.w600,
                      ),
                      semanticsLabel: 'User avatar $avatarText',
                    ),
                  ),
                );
              },

          onLeaveConfirmation: (context) async {
            return await showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Leave Meeting'),
                    content: const Text(
                      'Are you sure you want to leave the meeting?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Leave'),
                      ),
                    ],
                  ),
                ) ??
                false;
          },
          onError: (error) {
            logger.severe('Video conference error: $error');
            _showSnackBar(context, 'Meeting error occurred. Please try again.');
          },
        ),
      ),
    );
  }

  void _showSnackBar(
    BuildContext context,
    String message, {
    bool isError = true,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.poppins(color: Colors.white),
          semanticsLabel: message,
        ),
        backgroundColor: isError
            ? const Color(0xFFFF6B6B)
            : const Color(0xFF4E6DFF),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
        ),
      ),
    );
  }

  void _showErrorDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Configuration Error',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            semanticsLabel: 'Configuration Error',
          ),
          content: Text(
            'Invalid ZEGO configuration. Please contact support.',
            style: GoogleFonts.poppins(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'OK',
                style: GoogleFonts.poppins(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        );
      },
    ).then((_) => Navigator.pop(context));
  }
}

class _MeetingIdInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String text = newValue.text.replaceAll('-', '');

    if (text.length > 10) {
      text = text.substring(0, 10);
    }

    String formatted = '';
    for (int i = 0; i < text.length; i++) {
      if (i == 3 || i == 6) {
        formatted += '-';
      }
      formatted += text[i];
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
