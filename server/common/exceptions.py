import logging

from rest_framework import status
from rest_framework.exceptions import (
    AuthenticationFailed,
    NotAuthenticated,
    NotFound,
    PermissionDenied,
    Throttled,
    ValidationError,
)
from rest_framework.views import exception_handler

from .envelopes import error_response

logger = logging.getLogger("pocket_cfo.exceptions")


def pocket_cfo_exception_handler(exc, context):
    """Maps all DRF/application errors to `API_ERROR_CATALOGUE.md` stable codes.
    Never exposes tracebacks, SQL, or sensitive payloads to clients.
    """
    request = context.get("request")
    if isinstance(exc, ValidationError):
        field_errors = {}
        detail = exc.detail
        if isinstance(detail, dict):
            for k, v in detail.items():
                field_errors[str(k)] = [str(x) for x in (v if isinstance(v, list) else [v])]
        return error_response(
            "VALIDATION_ERROR",
            "Please check the submitted fields and try again.",
            request,
            status.HTTP_400_BAD_REQUEST,
            field_errors=field_errors,
        )

    if isinstance(exc, (NotAuthenticated, AuthenticationFailed)):
        return error_response(
            "AUTHENTICATION_REQUIRED",
            "Authentication credentials were missing, expired, or invalid.",
            request,
            status.HTTP_401_UNAUTHORIZED,
        )

    if isinstance(exc, PermissionDenied):
        return error_response(
            "PROFILE_ACCESS_DENIED",
            str(exc) or "You do not have access to this profile or action.",
            request,
            status.HTTP_403_FORBIDDEN,
        )

    if isinstance(exc, NotFound):
        return error_response(
            "RESOURCE_NOT_FOUND",
            "The requested resource was not found.",
            request,
            status.HTTP_404_NOT_FOUND,
        )

    if isinstance(exc, Throttled):
        return error_response(
            "RATE_LIMITED",
            "Rate limit exceeded. Please retry later.",
            request,
            status.HTTP_429_TOO_MANY_REQUESTS,
            retryable=True,
        )

    fallback = exception_handler(exc, context)
    if fallback is not None:
        return error_response(
            "VALIDATION_ERROR" if fallback.status_code < 500 else "INTERNAL_ERROR",
            "Request could not be processed.",
            request,
            fallback.status_code,
        )

    logger.error(
        "unhandled_server_exception",
        extra={"error_category": exc.__class__.__name__, "request_id": getattr(request, "request_id", None)},
    )
    return error_response(
        "INTERNAL_ERROR",
        "An unexpected server error occurred. Reference your request ID if contacting support.",
        request,
        status.HTTP_500_INTERNAL_SERVER_ERROR,
    )
