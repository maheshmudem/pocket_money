from django.db import connection
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny

from .envelopes import error_response, ok_response


@api_view(["GET"])
@permission_classes([AllowAny])
def health_live(request):
    return ok_response({"status": "alive"}, request)


@api_view(["GET"])
@permission_classes([AllowAny])
def health_ready(request):
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
            cursor.fetchone()
        return ok_response({"status": "ready", "database": "ok"}, request)
    except Exception:
        return error_response(
            "SERVER_UNAVAILABLE",
            "Database readiness check failed.",
            request,
            503,
            retryable=True,
        )
