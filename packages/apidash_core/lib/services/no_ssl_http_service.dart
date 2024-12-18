import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:seed/seed.dart';
import '../consts.dart';
import '../models/models.dart';
import '../utils/utils.dart';
import 'http_client_manager.dart';

typedef HttpResponse = http.Response;

/// Create a custom `HttpClient` with SSL verification disabled.
http.Client createHttpClientWithNoSSL() {
  var ioClient = HttpClient()
    ..badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
  return IOClient(ioClient);
}

Future<(HttpResponse?, Duration?, String?)> request(
  String requestId,
  HttpRequestModel requestModel, {
  SupportedUriSchemes defaultUriScheme = kDefaultUriScheme,
  bool bypassSSL = false,
}) async {
  final clientManager = HttpClientManager();
  final client = bypassSSL
      ? createHttpClientWithNoSSL() // Use SSL-bypassing client if specified
      : clientManager.createClient(requestId);

  (Uri?, String?) uriRec = getValidRequestUri(
    requestModel.url,
    requestModel.enabledParams,
    defaultUriScheme: defaultUriScheme,
  );
  if (uriRec.$1 != null) {
    Uri requestUrl = uriRec.$1!;
    Map<String, String> headers = requestModel.enabledHeadersMap;
    HttpResponse response;
    String? body;
    try {
      Stopwatch stopwatch = Stopwatch()..start();
      var isMultiPartRequest =
          requestModel.bodyContentType == ContentType.formdata;

      if (kMethodsWithBody.contains(requestModel.method)) {
        var requestBody = requestModel.body;
        if (requestBody != null && !isMultiPartRequest) {
          var contentLength = utf8.encode(requestBody).length;
          if (contentLength > 0) {
            body = requestBody;
            headers[HttpHeaders.contentLengthHeader] = contentLength.toString();
            if (!requestModel.hasContentTypeHeader) {
              headers[HttpHeaders.contentTypeHeader] =
                  requestModel.bodyContentType.header;
            }
          }
        }
        if (isMultiPartRequest) {
          var multiPartRequest = http.MultipartRequest(
            requestModel.method.name.toUpperCase(),
            requestUrl,
          );
          multiPartRequest.headers.addAll(headers);
          for (var formData in requestModel.formDataList) {
            if (formData.type == FormDataType.text) {
              multiPartRequest.fields.addAll({formData.name: formData.value});
            } else {
              multiPartRequest.files.add(
                await http.MultipartFile.fromPath(
                  formData.name,
                  formData.value,
                ),
              );
            }
          }
          http.StreamedResponse multiPartResponse =
              await multiPartRequest.send();
          stopwatch.stop();
          http.Response convertedMultiPartResponse =
              await http.Response.fromStream(multiPartResponse);
          return (convertedMultiPartResponse, stopwatch.elapsed, null);
        }
      }

      switch (requestModel.method) {
        case HTTPVerb.get:
          response = await client.get(requestUrl, headers: headers);
          break;
        case HTTPVerb.head:
          response = await client.head(requestUrl, headers: headers);
          break;
        case HTTPVerb.post:
          response =
              await client.post(requestUrl, headers: headers, body: body);
          break;
        case HTTPVerb.put:
          response = await client.put(requestUrl, headers: headers, body: body);
          break;
        case HTTPVerb.patch:
          response =
              await client.patch(requestUrl, headers: headers, body: body);
          break;
        case HTTPVerb.delete:
          response =
              await client.delete(requestUrl, headers: headers, body: body);
          break;
      }
      stopwatch.stop();
      return (response, stopwatch.elapsed, null);
    } catch (e) {
      if (clientManager.wasRequestCancelled(requestId)) {
        return (null, null, kMsgRequestCancelled);
      }
      return (null, null, e.toString());
    } finally {
      if (!bypassSSL) clientManager.closeClient(requestId);
      client.close(); // Always close the client
    }
  } else {
    return (null, null, uriRec.$2);
  }
}
