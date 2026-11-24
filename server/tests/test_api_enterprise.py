import uuid

import pytest
from rest_framework.test import APIClient

from apps.audit.models import AuditEvent
from common.logging_filters import sanitize_mapping, sanitize_text


@pytest.mark.django_db
class TestPocketCfoEnterpriseApi:
    def _register_and_auth(self, email: str, name: str, password: str = "StrongPass!2026"):
        client = APIClient()
        device_id = str(uuid.uuid4())
        res = client.post(
            "/api/v1/auth/register/",
            {
                "email": email,
                "password": password,
                "display_name": name,
                "device_id": device_id,
                "platform": "android",
                "app_version": "1.0.0+1",
            },
            format="json",
        )
        assert res.status_code == 201, res.content
        body = res.json()["data"]
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {body['access_token']}")
        return client, body, device_id

    def test_health_endpoints(self):
        client = APIClient()
        assert client.get("/api/v1/health/live/").status_code == 200
        ready = client.get("/api/v1/health/ready/")
        assert ready.status_code == 200
        assert ready.json()["data"]["database"] == "ok"

    def test_auth_refresh_rotation_and_reuse_detection_revokes_family(self):
        client, session, _ = self._register_and_auth("alice@example.com", "Alice")
        refresh_1 = session["refresh_token"]

        # First rotation succeeds and returns new refresh token.
        rot1 = client.post("/api/v1/auth/refresh/", {"refresh_token": refresh_1}, format="json")
        assert rot1.status_code == 200
        refresh_2 = rot1.json()["data"]["refresh_token"]
        assert refresh_2 != refresh_1

        # Replaying old refresh_1 MUST trigger reuse detection and revoke refresh_2 too!
        replay = client.post("/api/v1/auth/refresh/", {"refresh_token": refresh_1}, format="json")
        assert replay.status_code == 401

        rot2 = client.post("/api/v1/auth/refresh/", {"refresh_token": refresh_2}, format="json")
        assert rot2.status_code == 401
        assert AuditEvent.objects.filter(action="auth.refresh_reuse_detected").exists()

    def test_cross_profile_isolation_and_rbac_matrix(self):
        alice_client, _, _ = self._register_and_auth("owner@example.com", "Owner")
        bob_client, _, _ = self._register_and_auth("stranger@example.com", "Stranger")
        viewer_client, _, _ = self._register_and_auth("viewer@example.com", "Viewer")

        # Alice creates a Business profile.
        create_res = alice_client.post(
            "/api/v1/profiles/",
            {"name": "Studio", "profile_type": "business", "base_currency_code": "INR"},
            format="json",
        )
        assert create_res.status_code == 201
        profile_id = create_res.json()["data"]["id"]

        # Stranger Bob gets 403 PROFILE_ACCESS_DENIED on profile read, patch, members, and sync!
        for method, url in [
            ("get", f"/api/v1/profiles/{profile_id}/"),
            ("get", f"/api/v1/profiles/{profile_id}/members/"),
            ("get", f"/api/v1/sync/pull/?profile_id={profile_id}"),
        ]:
            resp = getattr(bob_client, method)(url)
            assert resp.status_code == 403
            assert resp.json()["error"]["code"] == "PROFILE_ACCESS_DENIED"

        # Alice invites Viewer with role=viewer.
        inv = alice_client.post(
            f"/api/v1/profiles/{profile_id}/members/",
            {"email": "viewer@example.com", "role": "viewer"},
            format="json",
        )
        assert inv.status_code == 201

        # Viewer CAN read profile, CANNOT patch settings, CANNOT post sync mutations.
        assert viewer_client.get(f"/api/v1/profiles/{profile_id}/").status_code == 200
        assert (
            viewer_client.patch(
                f"/api/v1/profiles/{profile_id}/", {"name": "Hacked"}, format="json"
            ).status_code
            == 403
        )

    def test_sync_idempotency_ledger_validation_immutability_conflict_and_cursor_pull(self):
        client, _, device_id = self._register_and_auth("sync@example.com", "Sync User")
        profile_id = client.post(
            "/api/v1/profiles/",
            {"name": "Personal", "profile_type": "personal", "base_currency_code": "INR"},
            format="json",
        ).json()["data"]["id"]

        tx_id = str(uuid.uuid4())
        op_id = str(uuid.uuid4())
        valid_tx_op = {
            "operation_id": op_id,
            "profile_id": profile_id,
            "entity_type": "transaction",
            "entity_id": tx_id,
            "operation_type": "create",
            "payload_version": 1,
            "base_version": None,
            "payload": {
                "status": "posted",
                "amount_minor": 50000,
                "postings": [
                    {"side": "debit", "base_amount_minor": 50000, "original_amount_minor": 50000},
                    {"side": "credit", "base_amount_minor": 50000, "original_amount_minor": 50000},
                ],
            },
        }

        # 1. Push valid balanced transaction -> accepted
        push1 = client.post(
            "/api/v1/sync/push/",
            {"device_id": device_id, "operations": [valid_tx_op]},
            format="json",
        )
        assert push1.status_code == 200
        assert push1.json()["data"]["results"][0]["outcome"] == "accepted"

        # 2. AC-SYNC-001: Replay exact same operation_id -> duplicate (no second effect!)
        push_replay = client.post(
            "/api/v1/sync/push/",
            {"device_id": device_id, "operations": [valid_tx_op]},
            format="json",
        )
        assert push_replay.json()["data"]["results"][0]["outcome"] == "duplicate"

        # 3. TC-FIN-008: Push unbalanced posted transaction -> permanent_error LEDGER_INVARIANT_VIOLATION
        bad_push = client.post(
            "/api/v1/sync/push/",
            {
                "device_id": device_id,
                "operations": [
                    {
                        "operation_id": str(uuid.uuid4()),
                        "profile_id": profile_id,
                        "entity_type": "transaction",
                        "entity_id": str(uuid.uuid4()),
                        "operation_type": "create",
                        "payload_version": 1,
                        "payload": {
                            "status": "posted",
                            "amount_minor": 1000,
                            "postings": [
                                {"side": "debit", "base_amount_minor": 1000, "original_amount_minor": 1000},
                                {"side": "credit", "base_amount_minor": 999, "original_amount_minor": 999},
                            ],
                        },
                    }
                ],
            },
            format="json",
        )
        assert bad_push.json()["data"]["results"][0]["error_code"] == "LEDGER_INVARIANT_VIOLATION"

        # 4. R-005: Attempt to mutate posted transaction -> permanent_error IMMUTABLE_POSTED_RECORD
        mutate_posted = client.post(
            "/api/v1/sync/push/",
            {
                "device_id": device_id,
                "operations": [
                    {
                        "operation_id": str(uuid.uuid4()),
                        "profile_id": profile_id,
                        "entity_type": "transaction",
                        "entity_id": tx_id,
                        "operation_type": "update",
                        "payload_version": 1,
                        "base_version": 1,
                        "payload": {"status": "posted", "amount_minor": 100, "postings": valid_tx_op["payload"]["postings"]},
                    }
                ],
            },
            format="json",
        )
        assert mutate_posted.json()["data"]["results"][0]["error_code"] == "IMMUTABLE_POSTED_RECORD"

        # 5. Draft optimistic conflict check (`ADR-012`)
        draft_id = str(uuid.uuid4())
        client.post(
            "/api/v1/sync/push/",
            {
                "device_id": device_id,
                "operations": [
                    {
                        "operation_id": str(uuid.uuid4()),
                        "profile_id": profile_id,
                        "entity_type": "transaction",
                        "entity_id": draft_id,
                        "operation_type": "create",
                        "payload_version": 1,
                        "payload": {"status": "draft", "amount_minor": 1000},
                    }
                ],
            },
            format="json",
        )
        conflict_push = client.post(
            "/api/v1/sync/push/",
            {
                "device_id": device_id,
                "operations": [
                    {
                        "operation_id": str(uuid.uuid4()),
                        "profile_id": profile_id,
                        "entity_type": "transaction",
                        "entity_id": draft_id,
                        "operation_type": "update",
                        "payload_version": 1,
                        "base_version": 99,  # stale version mismatch!
                        "payload": {"status": "draft", "amount_minor": 2000},
                    }
                ],
            },
            format="json",
        )
        assert conflict_push.json()["data"]["results"][0]["outcome"] == "conflict"

        # 6. Monotonic cursor pull returns changes and advances cursor
        pull1 = client.get(f"/api/v1/sync/pull/?profile_id={profile_id}")
        assert pull1.status_code == 200
        pull1_data = pull1.json()["data"]
        assert len(pull1_data["changes"]) == 2
        next_cursor = pull1_data["next_cursor"]

        pull2 = client.get(f"/api/v1/sync/pull/?profile_id={profile_id}&cursor={next_cursor}")
        assert pull2.json()["data"]["changes"] == []

    def test_device_revocation_invalidates_refresh_session(self):
        client, session, device_id = self._register_and_auth("dev@example.com", "Device User")
        assert len(client.get("/api/v1/devices/").json()["data"]) == 1

        rev = client.delete(f"/api/v1/devices/{device_id}/")
        assert rev.status_code == 204

        # Refresh token from revoked device MUST fail.
        ref = client.post(
            "/api/v1/auth/refresh/",
            {"refresh_token": session["refresh_token"]},
            format="json",
        )
        assert ref.status_code == 401

    def test_redacting_log_filter_strips_sensitive_data(self):
        clean = sanitize_mapping(
            {
                "password": "my-secret-password",
                "amount_minor": 50000,
                "description": "Salary credit",
                "safe_event": "sync_ok",
            }
        )
        assert clean["password"] == "[REDACTED]"
        assert clean["amount_minor"] == "[REDACTED]"
        assert clean["description"] == "[REDACTED]"
        assert clean["safe_event"] == "sync_ok"
        assert "alice@example.com" not in sanitize_text("Failed for alice@example.com")
