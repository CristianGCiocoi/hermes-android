import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/ws_client.dart';

Map<String, dynamic> readyWith(Object? capability) => <String, dynamic>{
  'jsonrpc': '2.0',
  'method': 'event',
  'params': <String, dynamic>{
    'type': 'gateway.ready',
    'payload': <String, dynamic>{
      'skin': <String, dynamic>{},
      if (capability != null)
        'capabilities': <String, dynamic>{
          'atlas_temporary_attachment': capability,
        },
    },
  },
};

void main() {
  test(
    'generic Gateway absence keeps ATLAS attachment capability disabled',
    () {
      final parsed = AtlasTemporaryAttachmentCapability.fromGatewayReady(
        readyWith(null),
      );
      expect(parsed.supported, isFalse);
    },
  );

  test('accepts only the exact optional Gateway attachment contract', () {
    final exact = <String, dynamic>{
      'contract': AtlasTemporaryAttachmentCapability.contract,
      'version': 1,
      'attach_method': 'file.attach',
      'promote_method': 'file.promote',
      'max_bytes': 64 * 1024 * 1024,
      'reserved': null,
    };
    // Unknown fields fail closed; the registered v1 capability has no
    // extensible client-authority bag.
    expect(
      AtlasTemporaryAttachmentCapability.fromGatewayReady(
        readyWith(exact),
      ).supported,
      isFalse,
    );
    exact.remove('reserved');
    expect(
      AtlasTemporaryAttachmentCapability.fromGatewayReady(
        readyWith(exact),
      ).supported,
      isTrue,
    );
  });

  test('wrong methods or unsafe limits fail closed', () {
    final drift = <String, dynamic>{
      'contract': AtlasTemporaryAttachmentCapability.contract,
      'version': 1,
      'attach_method': 'atlas.file.attach',
      'promote_method': 'file.promote',
      'max_bytes': 64 * 1024 * 1024 + 1,
    };
    expect(
      AtlasTemporaryAttachmentCapability.fromGatewayReady(
        readyWith(drift),
      ).supported,
      isFalse,
    );
  });

  test('file attach and explicit promote consume exact owner receipts', () async {
    const temporary = '51111111-1111-4111-8111-111111111111';
    const document = '61111111-1111-4111-8111-111111111111';
    const version = '71111111-1111-4111-8111-111111111111';
    final bytes = utf8.encode('fake');
    final contentHash = 'sha256:${sha256.convert(bytes)}';
    final requests = <Map<String, dynamic>>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.transform(WebSocketTransformer()).listen((
      socket,
    ) {
      socket.listen((raw) {
        final request = jsonDecode(raw as String) as Map<String, dynamic>;
        requests.add(request);
        if (request['method'] == 'file.attach') {
          socket.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': request['id'],
              'result': {
                'attached': true,
                'name': 'fixture.txt',
                'path': '/workspace/fixture.txt',
                'ref_path': 'fixture.txt',
                'ref_text': '@file:fixture.txt',
                'uploaded': true,
                'atlas_temporary': {
                  'authority': 'temporary-content-core',
                  'storage_authority': 'workspace-storage',
                  'document_id': null,
                  'temporary_content_id': temporary,
                  'content_kind': 'ATTACHMENT',
                  'mime_type': 'text/plain',
                  'size_bytes': bytes.length,
                  'content_hash': contentHash,
                  'storage_reference':
                      'workspace://0x_Temp/personal/$temporary/fixture.txt',
                  'origin_type': 'UPLOAD',
                  'origin_profile_id': 'personal',
                  'origin_session_id': 'conversation-1',
                  'origin_project_id': null,
                  'origin_channel': 'hermes-mobile',
                  'origin_producer_ref':
                      'hermes-mobile://owner-provider/upload',
                  'parent_temporary_content_id': null,
                  'created_at': '2026-08-16T10:00:00Z',
                  'updated_at': '2026-08-16T10:00:00Z',
                  'expires_at': '2026-08-17T10:00:00Z',
                  'retention_class': 'SHORT',
                  'lifecycle_status': 'AVAILABLE',
                  'processing_status': 'NOT_REQUESTED',
                  'promotion_status': 'NOT_REQUESTED',
                  'storage_status': 'AVAILABLE',
                  'retention_status': 'ACTIVE',
                  'revision': 1,
                  'provenance': {
                    'actor_profile_id': 'personal',
                    'conversation_ref': 'hermes://session/conversation-1',
                    'correlation_id': 'attach-client-1',
                    'evidence_ref':
                        'storage-receipt://workspace-storage/$temporary/$contentHash',
                  },
                  'failure_metadata': null,
                },
              },
            }),
          );
        } else {
          socket.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': request['id'],
              'result': {
                'promoted': true,
                'atlas_promotion': {
                  'authority': 'temporary-content-core',
                  'durable_authority': 'document-service',
                  'promotion_status': 'PROMOTED',
                  'receipt_id': '81111111-1111-4111-8111-111111111111',
                  'attempt_id': '91111111-1111-4111-8111-111111111111',
                  'temporary_content_id': temporary,
                  'document_id': document,
                  'document_version_id': version,
                  'idempotency_key': 'promote-client-1',
                  'request_digest': 'sha256:${List.filled(64, 'a').join()}',
                  'promoted_at': '2026-08-16T10:01:00Z',
                  'document_service_receipt_ref':
                      'document-service://promotion/$document/$version',
                },
              },
            }),
          );
        }
      });
    });
    final client = WsClient('http://127.0.0.1:${server.port}');
    try {
      await client.connect();
      final attached = await client.attachFile(
        sessionId: 'gateway-1',
        name: 'fixture.txt',
        dataUrl: 'data:text/plain;base64,${base64Encode(bytes)}',
        atlasConversationId: 'conversation-1',
        atlasProfileId: 'personal',
        atlasIdempotencyKey: 'attach-client-1',
        atlasMimeType: 'text/plain',
      );
      expect(attached.temporaryContentId, temporary);
      final promoted = await client.promoteFile(
        sessionId: 'gateway-1',
        temporaryContentId: temporary,
        conversationId: 'conversation-1',
        profileId: 'personal',
        idempotencyKey: 'promote-client-1',
      );
      expect(promoted['document_id'], document);
      expect((requests.first['params'] as Map)['atlas_temporary'], {
        'contract': AtlasTemporaryAttachmentCapability.contract,
        'profile_id': 'personal',
        'conversation_id': 'conversation-1',
        'idempotency_key': 'attach-client-1',
        'project_id': null,
        'mime_type': 'text/plain',
      });
      expect(
        (requests.last['params'] as Map).containsKey('authorization_digest'),
        isFalse,
      );
    } finally {
      client.close();
      await subscription.cancel();
      await server.close(force: true);
    }
  });
}
