from rest_framework.response import Response


def ok_response(data, request, status_code: int = 200) -> Response:
    return Response(
        {
            "data": data,
            "meta": {
                "request_id": getattr(request, "request_id", None),
            },
        },
        status=status_code,
    )


def error_response(
    code: str,
    message: str,
    request,
    status_code: int,
    *,
    retryable: bool = False,
    field_errors: dict | None = None,
) -> Response:
    return Response(
        {
            "error": {
                "code": code,
                "message": message,
                "retryable": retryable,
                "field_errors": field_errors or {},
            },
            "meta": {
                "request_id": getattr(request, "request_id", None),
            },
        },
        status=status_code,
    )
