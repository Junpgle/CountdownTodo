import 'package:http/http.dart' as http;
import 'timeout_http_client.dart';

http.Client createApiHttpClient() => TimeoutHttpClient(http.Client());
