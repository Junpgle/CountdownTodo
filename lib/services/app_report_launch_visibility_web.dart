import 'package:web/web.dart' as web;

bool get isReportLaunchPageVisible => web.document.visibilityState != 'hidden';
